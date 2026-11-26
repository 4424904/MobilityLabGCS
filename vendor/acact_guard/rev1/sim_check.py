#!/usr/bin/env python3
"""
sim_check.py — 오프라인 검증 시뮬레이터 (PX4·Gazebo 없이 수 초 만에 실행)
════════════════════════════════════════════════════════════════
- 4대를 질점 모델로 단순화 (가감속·상승률 제한, 미션 추종, Offboard 속도 추종)
- 가드(core.GuardCore)는 실기와 '같은 코드'를 그대로 사용
- GPS 오차(기체별 고정 편향 + 잡음), 텔레메트리 지연, 명령 지연 반영
- 결과: 기체 간 최소 이격거리, 개입 횟수, 비행 시간, 궤적 그림(PNG)

※ PX4 실제 동작을 완벽히 재현하지 않는다. 시나리오·파라미터 사전 점검용이며
  반드시 PX4 SITL(4대) → 현장 리허설(고도 분리) 순으로 추가 검증할 것.

사용:
  python3 sim_check.py                 # 전체 시나리오 demo 모드
  python3 sim_check.py S3_cross4 --mode rehearsal
  python3 sim_check.py --faults        # 통신 두절 등 고장 주입 시험 포함
"""
import argparse
import math
import os
import random
import sys

import config as C
import scenarios as SC
from core import GuardCore, DroneIn

DT = 0.05
ACC_H = 1.5
CLIMB_UP, CLIMB_DN = 1.5, 1.0
TKO_UP = C.TAKEOFF_SPEED
ACC_RAD = 2.0
LAND_V = 0.7
DL_LOSS_T = C.DL_LOSS_T
# ── 스트레스 시험용 (기본값 = 평상시) ──
TELEM_LAT = 0.15      # 텔레메트리 지연 [s]
TELEM_DROP = 0.0      # 텔레메트리 패킷 손실 확률
OB_SWITCH = 0.35      # PX4 Offboard 전환 지연 [s]
GUST = 0.0            # 돌풍·추종 오차 세기 [m/s] (무작위로 변하는 속도 교란)


class SimDrone:
    def __init__(self, did, prio, items, rng, gps_err=1.0):
        self.id, self.prio, self.items = did, prio, items
        h = items[0]["p"]
        self.f, self.r, self.u = h[0], h[1], 0.0
        self.vf = self.vr = self.vu = 0.0
        self.mode = "MISSION"
        self.idx = 0
        self.speed = C.TRANSIT_SPEED
        self.hold_until = None
        self.in_air = False
        self.landed = False
        self.ob_cmd = (0.0, 0.0, 0.0)
        self.ob_queue = []
        self.bias = (rng.uniform(-gps_err, gps_err), rng.uniform(-gps_err, gps_err))
        self.rng = rng
        self.link_lost_at = None
        self.ob_last_rx = -1e9
        self.trace = []
        self.layer = SC.LAYER[did]
        self.home = h
        self.sync_released = set()
        self.gust = (0.0, 0.0)

    # ── PX4 모사 ─────────────────────────────────────────
    def cur(self):
        return self.items[self.idx] if self.idx < len(self.items) else None

    def at_sync(self):
        it = self.cur()
        return self.mode == "MISSION" and it is not None and it["t"] == "sync" and self._reached(it)

    def _reached(self, it):
        return math.hypot(it["p"][0] - self.f, it["p"][1] - self.r) < ACC_RAD and abs(it.get("alt", 0) - self.u) < 0.8

    def _goto(self, p, alt, speed, stop):
        df, dr = p[0] - self.f, p[1] - self.r
        dist = math.hypot(df, dr)
        vmax = speed
        if stop:
            vmax = min(vmax, math.sqrt(2 * 1.0 * max(dist - 0.3, 0)) )
        else:
            vmax = min(vmax, math.sqrt(2 * 1.0 * dist) + 0.8)
        tf, tr = (df / dist * vmax, dr / dist * vmax) if dist > 0.05 else (0.0, 0.0)
        tu = max(-CLIMB_DN, min(CLIMB_UP, 1.0 * (alt - self.u)))
        return tf, tr, tu

    def step(self, t):
        tf = tr = tu = 0.0
        # 링크 끊김: offboard 중이면 1 s 후 HOLD, 5 s 후 RTL (PX4 데이터링크 상실 페일세이프 모사)
        if self.link_lost_at is not None and self.in_air:
            if self.mode == "OFFBOARD" and t - self.ob_last_rx > 1.0:
                self.mode = "HOLD"
            if t - self.link_lost_at > DL_LOSS_T and self.mode not in ("RTL", "LAND"):
                self.mode = "RTL"
                self.rtl_phase = 0
        # 지연된 offboard 명령 적용
        while self.ob_queue and self.ob_queue[0][0] <= t:
            _, kind, val = self.ob_queue.pop(0)
            if kind == "vel":
                self.ob_cmd = val
                self.ob_last_rx = t
            elif kind == "start" and self.mode in ("MISSION", "HOLD"):
                self.mode = "OFFBOARD"
            elif kind == "mission" and self.mode in ("OFFBOARD", "HOLD"):
                self.mode = "MISSION"
            elif kind == "advance" and self.idx + 1 < len(self.items):
                self.idx += 1
        if self.mode == "OFFBOARD":
            tf, tr, tu = self.ob_cmd
        elif self.mode == "HOLD":
            pass
        elif self.mode == "RTL":
            if self.rtl_phase == 0:
                tu = max(-CLIMB_DN, min(CLIMB_UP, self.layer + 0.0 - self.u))
                if abs(self.u - self.layer) < 0.5:
                    self.rtl_phase = 1
            elif self.rtl_phase == 1:
                tf, tr, tu = self._goto(self.home, self.layer, 3.0, True)
                if math.hypot(self.home[0] - self.f, self.home[1] - self.r) < 0.7:
                    self.rtl_phase = 2
            else:
                tu = -LAND_V
        elif self.mode == "MISSION" and not self.landed:
            it = self.cur()
            while it is not None and it["t"] == "speed":
                self.speed = it["v"]
                self.idx += 1
                it = self.cur()
            if it is None:
                pass
            elif it["t"] == "takeoff":
                tu = max(-CLIMB_DN, min(TKO_UP, it["alt"] - self.u))
                self.in_air = True
                if abs(it["alt"] - self.u) < 0.5:
                    self.idx += 1
            elif it["t"] == "land":
                tf, tr, _ = self._goto(it["p"], self.u, 1.0, True)
                tu = -LAND_V
            else:
                nxt_stop = it["t"] == "sync" or it.get("hold", 0) > 0
                tf, tr, tu = self._goto(it["p"], it["alt"], self.speed, nxt_stop or it["t"] == "sync")
                if self._reached(it):
                    if it["t"] == "sync":
                        if self.idx in self.sync_released:
                            self.idx += 1
                    elif it.get("hold", 0) > 0:
                        if self.hold_until is None:
                            self.hold_until = t + it["hold"]
                        if t >= self.hold_until:
                            self.hold_until = None
                            self.idx += 1
                    else:
                        self.idx += 1
        # 가속 제한
        dvf, dvr = tf - self.vf, tr - self.vr
        m = math.hypot(dvf, dvr)
        lim = ACC_H * DT
        if m > lim:
            dvf, dvr = dvf * lim / m, dvr * lim / m
        self.vf += dvf
        self.vr += dvr
        dvu = max(-1.0 * DT, min(1.0 * DT, tu - self.vu))
        self.vu += dvu
        if GUST > 0:
            gf, gr = self.gust
            gf += (-gf * 0.3 + self.rng.gauss(0, GUST * 0.6)) * DT
            gr += (-gr * 0.3 + self.rng.gauss(0, GUST * 0.6)) * DT
            k = math.hypot(gf, gr)
            if k > GUST:
                gf, gr = gf * GUST / k, gr * GUST / k
            self.gust = (gf, gr)
        else:
            gf = gr = 0.0
        self.f += (self.vf + gf) * DT
        self.r += (self.vr + gr) * DT
        self.u += self.vu * DT
        if self.u <= 0.0 and self.in_air and (self.mode in ("RTL",) or (self.cur() and self.cur()["t"] == "land")):
            self.u = 0.0
            self.landed = True
            self.in_air = False
            self.vf = self.vr = self.vu = 0.0
        self.u = max(self.u, 0.0)
        self.trace.append((t, self.f, self.r, self.u, self.mode))

    def measure(self, t):
        n = self.rng.gauss
        return (self.f + self.bias[0] + n(0, 0.3), self.r + self.bias[1] + n(0, 0.3),
                self.u + n(0, 0.3), self.vf + self.gust[0] + n(0, 0.1), self.vr + self.gust[1] + n(0, 0.1), self.vu + n(0, 0.1))

    def goal(self):
        it = self._nav()
        return it["p"] if it else None

    def _nav(self):
        # 실기 가드와 동일: 속도 변경 같은 비항법 항목은 건너뛰고 다음 항법 항목을 목표로
        k = self.idx
        while k < len(self.items) and "p" not in self.items[k]:
            k += 1
        return self.items[k] if k < len(self.items) else None

    def goal_alt(self):
        it = self._nav()
        return it.get("alt") if it else None

    def goal_hold(self):
        it = self._nav()
        return bool(it) and (it["t"] == "sync" or it.get("hold", 0) > 0)


def mode_name(m):
    return {"RTL": "RTL", "LAND": "LAND"}.get(m, m)


def run(name, mode="demo", seed=1, fault=None, gps_err=1.0, plot=True, verbose=False, outdir="sim_out"):
    rng = random.Random(seed)
    built = SC.build(name, mode)
    drones = [SimDrone(d, i, built[d], rng, gps_err) for i, d in enumerate(SC.IDS)]
    guard = GuardCore(SC.IDS)
    # 이륙 순차 (실제 운용: 높은 층부터 D4→D1, 5초 간격 — 낮은 층 기체가 위 기체의 상승 경로를 가로지르지 않도록)
    start_t = {d.id: 5.0 * (len(drones) - 1 - i) for i, d in enumerate(drones)}
    t = 0.0
    tele = {}   # 가드가 보는 최신 측정 (지연 반영)
    tele_q = []
    last_rx = {d.id: -1e9 for d in drones}
    events = []
    sync_pending_since = None
    sync_count = 0
    first_sync_t = None
    scenario_end_t = None
    fault_done = False
    takeovers = 0
    T_MAX = 900
    while t < T_MAX:
        for d in drones:
            if t >= start_t[d.id]:
                d.step(t)
        # 고장 주입
        if fault and not fault_done:
            fid, ft_rel = fault
            if first_sync_t is not None and t >= first_sync_t + ft_rel:
                for d in drones:
                    if d.id == fid:
                        d.link_lost_at = t
                events.append((t, fid, "고장주입: 텔레메트리 차단"))
                fault_done = True
        # 텔레메트리 10 Hz, 지연 0.15 s
        if int(round(t / DT)) % int(1 / (C.TELEM_HZ * DT)) == 0:
            for d in drones:
                if d.link_lost_at is None and t >= start_t[d.id] and not (TELEM_DROP and rng.random() < TELEM_DROP):
                    tele_q.append((t + TELEM_LAT, d.id, d.measure(t), d.mode, d.in_air, d.u, (d.goal(), d.goal_hold(), d.goal_alt())))
        while tele_q and tele_q[0][0] <= t:
            _, did, meas, md, ia, ru, gl = tele_q.pop(0)
            tele[did] = (meas, md, ia, ru, gl)
            last_rx[did] = t
        # 가드 20 Hz
        if int(round(t / DT)) % int(1 / (C.LOOP_HZ * DT)) == 0:
            ins = []
            for d in drones:
                if d.id not in tele:
                    continue
                meas, md, ia, ru, gl = tele[d.id]
                age = t - last_rx[d.id]
                ins.append(DroneIn(d.id, d.prio, age < C.STALE_T, age, meas[0], meas[1], meas[2],
                                   meas[3], meas[4], meas[5], ru, ia, md, gl[0], d.layer, gl[1], gl[2],
                                   (d.home[0] + d.bias[0], d.home[1] + d.bias[1])))   # PX4 홈도 같은 GPS 로 기록되므로 같은 오차
            for cmd in guard.step(t, ins):
                kind, did, val = cmd
                dd = next((x for x in drones if x.id == did), None)
                if kind == "event":
                    events.append((t, did, val))
                    continue
                if dd is None or dd.link_lost_at is not None:
                    continue
                if kind == "takeover":
                    takeovers += 1
                    dd.ob_queue.append((t + 0.1, "vel", val))
                    dd.ob_queue.append((t + OB_SWITCH, "start", None))   # PX4 모드 전환 지연
                    events.append((t, did, "개입"))
                elif kind == "vel":
                    dd.ob_queue.append((t + 0.1, "vel", val))
                elif kind == "advance":
                    dd.ob_queue.append((t + 0.2, "advance", None))
                elif kind == "release":
                    dd.ob_queue.append((t + 0.3, "mission", None))
                    events.append((t, did, "미션 복귀"))
        # 동기('g') 자동: 살아있는 공중 기체가 모두 SYNC 도달 → 3 s 후 해제 (실제: 운용자 'g')
        alive = [d for d in drones if d.in_air and d.link_lost_at is None and d.mode in ("MISSION", "OFFBOARD", "HOLD")]
        if alive and all(d.at_sync() for d in alive):
            nxt = alive[0].items[alive[0].idx + 1] if alive[0].idx + 1 < len(alive[0].items) else {}
            cur_sync = alive[0].items[alive[0].idx]
            is_start = cur_sync.get("tag") == "start"
            is_end = cur_sync.get("tag") == "end"
            if is_end and scenario_end_t is None and first_sync_t is not None:
                scenario_end_t = t
            if sync_pending_since is None:
                sync_pending_since = t
            delay = 3.0
            if fault and first_sync_t is not None and not is_end and not is_start:
                delay = 25.0          # S6: 거점 대기 중 링크 차단 시연 시간
            if t - sync_pending_since >= delay:
                for d in alive:
                    d.sync_released.add(d.idx)
                sync_count += 1
                if is_start and first_sync_t is None:
                    first_sync_t = t
                events.append((t, "ALL", f"동기 출발 #{sync_count}" + (" (시나리오 시작)" if is_start else "")))
                sync_pending_since = None
        else:
            sync_pending_since = None
        if all(d.landed for d in drones):
            break
        t += DT

    # 결과
    true_min3d, true_minh = {}, {}
    n = min(len(d.trace) for d in drones)
    tr = {d.id: d.trace for d in drones}
    for i in range(len(drones)):
        for j in range(i + 1, len(drones)):
            a, b = drones[i].id, drones[j].id
            m3, mh = 1e9, 1e9
            ta, tb = tr[a], tr[b]
            # 시간 정렬 (이륙 지연 반영)
            off = int(round((start_t[b] - start_t[a]) / DT))
            for k in range(len(tb)):
                ka = k + off
                if ka < 0 or ka >= len(ta):
                    continue
                _, fa, ra, ua, _ = ta[ka]
                _, fb, rb, ub, _ = tb[k]
                if ua < 3 or ub < 3:
                    continue
                dh = math.hypot(fa - fb, ra - rb)
                m3 = min(m3, math.sqrt(dh * dh + (ua - ub) ** 2))
                if abs(ua - ub) <= C.V_SEP:
                    mh = min(mh, dh)
            true_min3d[(a, b)], true_minh[(a, b)] = m3, mh
    res = {
        "name": name, "mode": mode, "seed": seed, "fault": fault,
        "flight_time": t,
        "demo_time": (scenario_end_t - first_sync_t) if (scenario_end_t and first_sync_t) else None,
        "min3d": min(true_min3d.values()),
        "min3d_pair": min(true_min3d, key=true_min3d.get),
        "minh_same_layer": min(true_minh.values()),
        "takeovers": takeovers,
        "owned_time": {k: round(v.owned_time, 1) for k, v in guard.own.items()},
        "events": events,
        "all_landed": all(d.landed for d in drones),
        "pairs_min3d": true_min3d,
    }
    if plot:
        _plot(res, drones, outdir)
    return res


def _plot(res, drones, outdir):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    os.makedirs(outdir, exist_ok=True)
    fig, ax = plt.subplots(figsize=(7, 7.6))
    cols = {"D1": "#d62728", "D2": "#1f77b4", "D3": "#2ca02c", "D4": "#9467bd"}
    for d in drones:
        xs = [p[2] for p in d.trace if p[3] > 1]
        ys = [p[1] for p in d.trace if p[3] > 1]
        ax.plot(xs, ys, color=cols[d.id], lw=1.0, alpha=0.6, label=d.id)
        ox = [p[2] if p[4] == "OFFBOARD" else float("nan") for p in d.trace if p[3] > 1]
        oy = [p[1] if p[4] == "OFFBOARD" else float("nan") for p in d.trace if p[3] > 1]
        ax.plot(ox, oy, color=cols[d.id], lw=3.0)
        ax.plot(d.home[1], d.home[0], "s", color=cols[d.id])
    circ = plt.Circle((0, 0), C.SCENARIO_RADIUS, fill=False, ls=":", color="gray")
    ax.add_patch(circ)
    if C.PROFILE == "hwaseong":
        from matplotlib.patches import Rectangle
        ax.add_patch(Rectangle((-10.5, -52.5), 21, 21, fill=False, ls="-", color="gray"))
        ax.axhline(-28.5, color="#BA7517", lw=1.2, ls="--")
        ax.text(30, -27.5, "fence", fontsize=8, color="#BA7517")
        ax.text(0, -56, "helipad 2 (21x21 m)", ha="center", fontsize=8, color="gray")
    else:
        ax.axhline(C.HOME_LINE_F, color="gray", lw=0.5)
        ax.text(0, C.HOME_LINE_F - 4, "takeoff line / GCS side", ha="center", fontsize=8, color="gray")
    ax.set_aspect("equal")
    ax.set_xlim(-45, 45)
    ax.set_ylim(-60, 40)
    ax.set_xlabel("Right [m]")
    ax.set_ylabel("Forward [m]")
    ax.grid(alpha=0.3)
    ax.legend(loc="upper right", fontsize=8)
    a, b = res["min3d_pair"]
    ax.set_title(f"{res['name']} ({res['mode']}) — min sep {res['min3d']:.1f} m ({a}-{b}), "
                 f"takeovers {res['takeovers']}\nthick = guard avoidance (Offboard)", fontsize=9)
    fn = os.path.join(outdir, f"{res['name']}_{res['mode']}{'_fault' if res['fault'] else ''}{'_hwaseong' if C.PROFILE == 'hwaseong' else ''}.png")
    fig.savefig(fn, dpi=110, bbox_inches="tight")
    plt.close(fig)
    res["png"] = fn


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--drones", default=None, help="일부 기체만 (예: D1,D3). 생략 시 4대")
    ap.add_argument("names", nargs="*")
    ap.add_argument("--mode", default="demo", choices=["demo", "rehearsal"])
    ap.add_argument("--seeds", type=int, default=5)
    ap.add_argument("--faults", action="store_true")
    ap.add_argument("-v", action="store_true")
    ap.add_argument("--profile", default=C.PROFILE, choices=list(C.HOME_LAYOUTS))
    a = ap.parse_args()
    C.PROFILE = a.profile
    print(f"프로파일: {a.profile}")
    names = a.names or [n for n in SC.SCENARIOS if SC.available(n)]
    print(f"{'시나리오':<14}{'모드':<10}{'최소이격(3D)':>12}{'최악 seed':>10}{'개입':>6}{'시연구간':>9}{'총비행':>8}  착륙")
    for n in names:
        rs = [run(n, a.mode, seed=s, plot=(s == 1)) for s in range(1, a.seeds + 1)]
        worst = min(rs, key=lambda r: r["min3d"])
        avg_to = sum(r["takeovers"] for r in rs) / len(rs)
        dt = worst["demo_time"]
        print(f"{n:<14}{a.mode:<10}{worst['min3d']:>10.1f} m{worst['seed']:>10}{avg_to:>6.1f}"
              f"{(f'{dt:.0f}s' if dt else '-'):>9}{worst['flight_time']:>7.0f}s  {'OK' if all(r['all_landed'] for r in rs) else 'NG'}")
        if a.v:
            for e in worst["events"]:
                print(f"     t={e[0]:6.1f} {e[1]:>5} {e[2]}")
    if a.faults:
        print("\n고장 주입 시험 (demo 모드)")
        for n, fault in [("S3_cross4", ("D1", 5.0)), ("S3_cross4", ("D2", 8.0)),
                         ("S2_headon", ("D1", 6.0)), ("S6_linkloss", ("D2", 1.0))]:
            rs = [run(n, "demo", seed=s, fault=fault, plot=(s == 1)) for s in range(1, a.seeds + 1)]
            worst = min(rs, key=lambda r: r["min3d"])
            print(f"  {n:<12} {fault[0]} 링크 차단 (동기 후 {fault[1]:.0f}s): 최소이격 {worst['min3d']:.1f} m, "
                  f"착륙 {'OK' if all(r['all_landed'] for r in rs) else 'NG'}")
            if a.v:
                for e in worst["events"]:
                    print(f"     t={e[0]:6.1f} {e[1]:>5} {e[2]}")


if __name__ == "__main__":
    main()
