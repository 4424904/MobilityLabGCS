"""
core.py — ACACT Guard 판단 로직 (MAVSDK 비의존, 실기·오프라인 시뮬 공용)
════════════════════════════════════════════════════════════════
좌표: 시연 프레임 2D (F, R) + 고도 U(위 +)
GuardCore.step() 은 기체 상태 목록을 받아 '명령 목록'을 돌려준다.
  ("takeover", id, (vF, vR, vU))   : Offboard 진입 + 회피 속도
  ("vel",      id, (vF, vR, vU))   : 회피 속도 갱신
  ("release",  id, None)           : 미션 복귀
  ("event",    id, text)           : 로그/화면용 이벤트
"""
import math
from dataclasses import dataclass, field
from typing import Optional, List, Dict, Tuple

import config as C

EPS = 1e-9


def _norm(x, y):
    return math.hypot(x, y)


# ═══════════════════════════════════════════════════════════════
# 상태 입력
# ═══════════════════════════════════════════════════════════════
@dataclass
class DroneIn:
    id: str
    prio: int                 # 0 = 최우선 (D1)
    fresh: bool               # 텔레메트리 최신 여부
    age: float                # 마지막 수신 후 경과 [s]
    f: float
    r: float
    u: float                  # 고도 (공통 기준) [m]
    vf: float
    vr: float
    vu: float
    rel_alt: float            # 이륙지점 기준 고도
    in_air: bool
    mode: str                 # MISSION / OFFBOARD / HOLD / RTL / LAND / TAKEOFF / MANUAL / OTHER
    goal: Optional[Tuple[float, float]] = None   # 현재 미션 목표 (F, R)
    rtl_alt: float = 0.0      # PX4 RTL 고도 (이륙지점 기준) — 통신 끊김 후 상승 예측용
    goal_hold: bool = False   # 목표가 정지(대기·hold) 지점인지
    goal_alt: Optional[float] = None   # 현재 미션 목표 고도 (이륙지점 기준) — 수직 예측을 목표 고도에서 멈추게
    home: Optional[Tuple[float, float]] = None     # 이륙지점 (F, R) — 이륙 구역 판정용


@dataclass
class _Own:
    owned: bool = False
    t_take: float = 0.0
    t_clear: Optional[float] = None
    hold_u: float = 0.0
    lock: bool = False        # 조종자 개입 → 미션 재개 전까지 손대지 않음
    yielding: bool = False    # 합류 양보 중
    t_handoff: float = -1e9   # 목표 도달로 미션에 넘긴 시각
    takeovers: int = 0
    owned_time: float = 0.0


@dataclass
class PairEval:
    level: int                # 0 정상, 1 위험(CPA), 2 긴급
    d_now: float
    d_cpa: float
    t_cpa: float
    dz: float
    clear: bool               # 해제 기준(히스테리시스) 충족


# ═══════════════════════════════════════════════════════════════
# 기하
# ═══════════════════════════════════════════════════════════════
def predicted(d: DroneIn):
    """
    STALE(통신 끊김) 기체는 계속 갔는지 멈췄는지 모른다.
    → '마지막 위치'와 '계속 갔을 위치'를 모두 덮는 원으로 취급한다.
      중심 = 마지막 위치 + 속도×경과/2,  반경 확대 = 속도×경과/2 + 경과×0.5 m/s (최대 10 m)
    PX4 는 COM_DL_LOSS_T 후 RTL → 먼저 RTL 고도(기체별 층)로 수직 상승한다.
    → 그 시간이 지나면 층 고도로 올라갔다고 보고 같은 층 판정에서 뺀다.
    """
    if d.fresh:
        return d.f, d.r, d.u, d.vf, d.vr, 0.0
    a = min(d.age, C.STALE_PREDICT_MAX)
    sp = _norm(d.vf, d.vr)
    infl = min(sp * a / 2.0 + 0.5 * a, 10.0)
    u = d.u
    climb = max(d.rtl_alt - d.rel_alt, 0.0)
    if d.age > C.DL_LOSS_T + climb / 1.0 + 2.0:
        u = d.u + climb
    return d.f + d.vf * a / 2.0, d.r + d.vr * a / 2.0, u, 0.0, 0.0, infl


def cpa(pf, pr, vf, vr, t_look):
    """상대위치 p, 상대속도 v → (t_cpa, d_cpa)"""
    vv = vf * vf + vr * vr
    if vv < 1e-6:
        return 0.0, _norm(pf, pr)
    t = -(pf * vf + pr * vr) / vv
    t = max(0.0, min(t, t_look))
    return t, _norm(pf + vf * t, pr + vr * t)


def eval_pair(a: DroneIn, b: DroneIn, extra: float = 0.0) -> PairEval:
    af, ar, au, avf, avr, ia = predicted(a)
    bf, br, bu, bvf, bvr, ib = predicted(b)
    infl = ia + ib + extra
    dz = abs(au - bu)
    pf, pr = bf - af, br - ar
    vf, vr = bvf - avf, bvr - avr
    d_now = _norm(pf, pr)
    t_c, d_c = cpa(pf, pr, vf, vr, C.T_LOOK)
    # 수직: 최근접 시점의 예상 고도차로 판단.
    #   상승/하강 중인 기체는 미션 목표 고도에서 멈추므로 그 이상은 외삽하지 않는다
    #   (예: 헬리패드에서 층 고도로 상승 중인 기체를 위 기체와 충돌로 오판하지 않도록)
    def _u_at(d: DroneIn, u0, tt):
        if not d.fresh or abs(d.vu) < 0.4:
            return u0
        if d.goal_alt is not None and abs(d.goal_alt - d.rel_alt) < 1.0:
            return u0            # 목표 고도 도달 상태 → 고도 유지로 본다 (센서 잡음 외삽 방지)
        u1 = u0 + d.vu * tt
        if d.goal_alt is not None:
            g = u0 + (d.goal_alt - d.rel_alt)
            if (d.vu > 0 and g >= u0) or (d.vu < 0 and g <= u0):
                u1 = min(u1, g) if d.vu > 0 else max(u1, g)
        return u1
    # 두 기체 모두 제자리에서 수직 이동만 하는 중(이륙·착륙 기둥)이면 수평거리는 변하지 않는다
    #   → 긴급 거리 밖이면 충돌 아님 (헬리패드 2×2 처럼 10 m 간격 이착륙)
    def _vert_only(d: DroneIn):
        if not d.fresh or _norm(d.vf, d.vr) > 0.5:
            return False
        return d.goal is None or _norm(d.goal[0] - d.f, d.goal[1] - d.r) < 2.5
    if _vert_only(a) and _vert_only(b) and d_now > C.D_EMERG:
        return PairEval(0, d_now, d_c, t_c, dz, True)

    # 둘 다 자기 이륙지점 근처(이륙·앞으로 2 m·착륙 구역)에 있으면 정해진 자리 안에서만 움직이므로 충돌 아님
    def _on_pad(d: DroneIn):
        return d.fresh and d.home is not None and _norm(d.f - d.home[0], d.r - d.home[1]) < C.PAD_ZONE
    if _on_pad(a) and _on_pad(b) and d_now > C.D_EMERG:
        return PairEval(0, d_now, d_c, t_c, dz, True)

    # 둘 다 서로 떨어진 대기점(정지 지점)에 거의 도착해 자리를 잡는 중이면 충돌 아님
    #   (GPS 오차로 대기점 간격이 D_SAFE 보다 약간 작게 보여도 '개입 → 복귀 → 개입' 이 반복되지 않도록)
    def _settling(d: DroneIn):
        return (d.fresh and d.goal_hold and d.goal is not None
                and _norm(d.goal[0] - d.f, d.goal[1] - d.r) < 4.0 and _norm(d.vf, d.vr) < 1.5)
    if _settling(a) and _settling(b) and d_now > C.D_EMERG \
            and _norm(a.goal[0] - b.goal[0], a.goal[1] - b.goal[1]) > C.D_EMERG + 2.0:
        return PairEval(0, d_now, d_c, t_c, dz, True)
    dz_cpa = abs(_u_at(a, au, t_c) - _u_at(b, bu, t_c))
    dz_mid = abs(_u_at(a, au, t_c / 2) - _u_at(b, bu, t_c / 2))
    if min(dz, dz_cpa, dz_mid) > C.V_SEP:
        return PairEval(0, d_now, d_c, t_c, dz, True)
    # 서로 거의 같은 속도로 나란히 움직이는 쌍(이륙 후 함께 전진 등)은 거리가 줄지 않으므로 충돌 아님
    #   (서로 다가오는 속도가 0.3 m/s 이하 = 거리가 줄지 않음)
    closing = -(pf * vf + pr * vr) / max(d_now, 1e-3)
    if a.fresh and b.fresh and closing < 0.3 and _norm(vf, vr) < 1.0 and d_now > C.D_EMERG + 1.0:
        return PairEval(0, d_now, d_c, t_c, dz, d_now > C.D_SAFE + C.RELEASE_MARGIN)
    level = 0
    if d_now < C.D_EMERG + infl:
        level = 2
    elif d_now < C.D_SAFE + infl or (d_c < C.D_SAFE + infl and t_c < C.T_LOOK):
        level = 1
    rel = C.D_SAFE + C.RELEASE_MARGIN + infl
    clear = d_now > rel and (d_c > rel or t_c >= C.T_LOOK)
    return PairEval(level, d_now, d_c, t_c, dz, clear)


# ═══════════════════════════════════════════════════════════════
# ACACT 2D (우측 통행 보정 포함)
# ═══════════════════════════════════════════════════════════════
def _acact_adapt(vf, vr, rf, rr, ts):
    """논문 식 (12)-(15): 예측 충돌시간 tc < ts 이면 장애물 방향 성분을 줄인다."""
    rm = _norm(rf, rr)
    vm = _norm(vf, vr)
    if rm < EPS or vm < EPS:
        return vf, vr
    dot = vf * rf + vr * rr          # r = 나 ← 장애물
    if dot >= 0:
        return vf, vr                 # 멀어지는 중
    tc = rm * rm / (-dot)
    if tc >= ts:
        return vf, vr
    vp_plus = rm / ts
    rhf, rhr = rf / rm, rr / rm
    proj = vf * rhf + vr * rhr
    pf_, pr_ = proj * rhf, proj * rhr
    qf, qr = vf - pf_, vr - pr_
    pn, qn = _norm(pf_, pr_), _norm(qf, qr)
    pfu, pru = (pf_ / pn, pr_ / pn) if pn > EPS else (0.0, 0.0)
    qfu, qru = (qf / qn, qr / qn) if qn > EPS else (0.0, 0.0)
    rem = max(vm * vm - vp_plus * vp_plus, 0.0)
    s = math.sqrt(rem)
    return vp_plus * pfu + s * qfu, vp_plus * pru + s * qru


def acact_velocity(me: DroneIn, others: List[DroneIn], goal, emergency=False):
    p = C.ACACT
    af, ar = goal[0] - me.f, goal[1] - me.r
    am = _norm(af, ar)
    # 인력: 목표 방향, 크기는 순항속도로 제한 (반발력이 묻히지 않도록 먼저 제한)
    sa = min(p["kpa"] * am, C.MAX_H_SPEED)
    vf, vr = (sa * af / am, sa * ar / am) if am > p["goal_tol"] else (0.0, 0.0)

    hf, hr = (me.vf, me.vr) if _norm(me.vf, me.vr) > 0.3 else (af, ar)
    hm = _norm(hf, hr)
    hf, hr = (hf / hm, hr / hm) if hm > EPS else (1.0, 0.0)
    rightf, rightr = -hr, hf          # 진행방향 기준 오른쪽

    rpf = rpr = 0.0
    rvf = rvr = 0.0
    bf = br = 0.0
    best, best_tc = None, float("inf")
    for nb in others:
        if nb.id == me.id:
            continue
        nf, nr, nu, nvf, nvr, infl = predicted(nb)
        if abs(nu - me.u) > C.V_SEP + 2.0:
            continue
        rf, rr = me.f - nf, me.r - nr
        rm = _norm(rf, rr)
        rs = p["rs"] + infl
        # 예측 최근접점(CPA) 기반 우측 회피: 반발 반경 밖에서도 미리 오른쪽으로 비켜 나간다
        t_c, d_c = cpa(nf - me.f, nr - me.r, nvf - me.vf, nvr - me.vr, C.T_LOOK)
        lim = C.D_SAFE + 3.0 + infl
        if t_c < C.T_LOOK and d_c < lim and t_c > 0.0:
            g = p["k_cpa"] * (lim - d_c) / lim
            bf += g * rightf
            br += g * rightr
        if rm >= rs:
            continue
        rm = max(rm, 0.5)
        rhf, rhr = rf / rm, rr / rm
        k = rs * rs / (rm * rm) - 1.0          # 반경 경계에서 0 → 연속 (급격한 튐 방지)
        rpf += k * rhf
        rpr += k * rhr
        # 상대속도 반발 (식 5-6)
        vrf, vrr = nvf - me.vf, nvr - me.vr
        vrm = _norm(vrf, vrr)
        if vrm > EPS:
            vhf, vhr = vrf / vrm, vrr / vrm
            d = rhf * vhf + rhr * vhr
            if 0.0 < d < 1.0:
                rvf += rhf / d - vhf
                rvr += rhr / d - vhr
        # 접근 판정은 상대속도 기준, tc = r² / 접근률 (단위: s)
        closing = -(rf * (me.vf - nvf) + rr * (me.vr - nvr))
        if closing > EPS:
            tc = rm * rm / closing
            if tc < best_tc:
                best_tc, best = tc, (rf, rr)
            if tc < 2.0 * p["ts"]:
                g = p["k_rh"] * (rs / rm - 1.0)
                bf += g * rightf
                brr = g * rightr
                br += brr

    if emergency:
        # 긴급: 반발 방향으로만 천천히 이탈
        m = _norm(rpf, rpr)
        vf, vr = ((rpf / m) * 1.0, (rpr / m) * 1.0) if m > EPS else (0.0, 0.0)
        return vf, vr, {"mode": "EMERG", "tc": best_tc}

    vf += p["kpp"] * rpf + p["kpv"] * rvf + bf
    vr += p["kpp"] * rpr + p["kpv"] * rvr + br

    stuck = am > 2.0 and _norm(vf, vr) < 0.3
    if stuck:   # 교착 탈출: 목표 방향 기준 오른쪽으로 비켜 나감 (결정적, 무작위 X)
        gm = am if am > EPS else 1.0
        vf, vr = 1.0 * (-ar / gm), 1.0 * (af / gm)
    elif best is not None:
        vf, vr = _acact_adapt(vf, vr, best[0], best[1], p["ts"])

    m = _norm(vf, vr)
    if m > C.MAX_H_SPEED:
        vf, vr = vf * C.MAX_H_SPEED / m, vr * C.MAX_H_SPEED / m
    return vf, vr, {"mode": "STUCK" if stuck else "ACACT", "tc": best_tc}


# ═══════════════════════════════════════════════════════════════
# 가드 상태기계
# ═══════════════════════════════════════════════════════════════
class GuardCore:
    def __init__(self, ids: List[str]):
        self.own: Dict[str, _Own] = {i: _Own() for i in ids}
        self.pairs: Dict[Tuple[str, str], PairEval] = {}
        self.min_sep: Dict[Tuple[str, str], float] = {}   # 같은 층(V_SEP 이내) 최소 수평거리
        self.min_3d: Dict[Tuple[str, str], float] = {}
        self.enabled = True
        self._last_t = None
        self._warned_t = {}
        self._dropped = set()
        self._extra = 0.0

    def eligible(self, d: DroneIn) -> bool:
        o = self.own[d.id]
        if not d.fresh or not d.in_air or d.rel_alt < C.MIN_TAKEOVER_ALT or o.lock:
            return False
        return d.mode == "MISSION" or (d.mode == "OFFBOARD" and o.owned)

    def step(self, t: float, drones: List[DroneIn]):
        cmds = []
        dt = 0.0 if self._last_t is None else t - self._last_t
        self._last_t = t
        by = {d.id: d for d in drones}

        # 1) 쌍 평가
        # 통신 두절 STALE_DROP_T 초 경과 기체는 PX4 RTL 로 귀환 중이라고 보고 판단에서 제외 (위치 추정 불가)
        for d in drones:
            if not d.fresh and d.age > C.STALE_DROP_T and d.in_air:
                if d.id not in self._dropped:
                    self._dropped.add(d.id)
                    cmds.append(("event", d.id, f"통신 두절 {C.STALE_DROP_T:.0f}초 — RTL 귀환 중으로 간주, 충돌 판단에서 제외 (육안 확인!)"))
            elif d.fresh:
                self._dropped.discard(d.id)
        drones = [d for d in drones if d.id not in self._dropped]
        # 통신이 끊긴 기체가 있으면(위치 불확실) 나머지 기체끼리도 여유 거리를 2 m 더 둔다
        self._extra = C.DEGRADED_MARGIN if any(d.in_air and not d.fresh for d in drones) else 0.0
        risk = {d.id: 0 for d in drones}
        clear_all = {d.id: True for d in drones}
        self.pairs = {}
        for i in range(len(drones)):
            for j in range(i + 1, len(drones)):
                a, b = drones[i], drones[j]
                if not (a.in_air and b.in_air):
                    continue
                pe = eval_pair(a, b, self._extra)
                key = (a.id, b.id)
                self.pairs[key] = pe
                if a.fresh and b.fresh:
                    d3 = math.sqrt(pe.d_now ** 2 + pe.dz ** 2)
                    self.min_3d[key] = min(self.min_3d.get(key, 1e9), d3)
                    if pe.dz <= C.V_SEP:
                        self.min_sep[key] = min(self.min_sep.get(key, 1e9), pe.d_now)
                risk[a.id] = max(risk[a.id], pe.level)
                risk[b.id] = max(risk[b.id], pe.level)
                if not pe.clear:
                    clear_all[a.id] = clear_all[b.id] = False
                if pe.level >= 1 and not (self.eligible(a) or self.own[a.id].owned) \
                        and not (self.eligible(b) or self.own[b.id].owned):
                    if t - self._warned_t.get(key, -1e9) > 10.0:
                        self._warned_t[key] = t
                        cmds.append(("event", f"{a.id}-{b.id}",
                                     f"위험 근접 {pe.d_now:.1f}m — 두 기체 모두 개입 불가 (모드 {a.mode}/{b.mode})"))

        # 2) 기체별 상태기계
        for d in drones:
            o = self.own[d.id]
            if o.owned:
                o.owned_time += dt
            # 조종자/PX4 가 모드를 바꿈 → 손 뗀다
            if o.owned and d.fresh and d.mode != "OFFBOARD" and t - o.t_take > 1.5:
                o.owned = False
                if d.mode != "MISSION":
                    o.lock = True
                    cmds.append(("event", d.id, f"모드 {d.mode} 전환 감지 → 가드 해제 (미션 재개 시 다시 감시)"))
                continue
            if o.lock and d.mode == "MISSION":
                o.lock = False
            if o.owned and not d.fresh:
                o.owned = False
                cmds.append(("event", d.id, "텔레메트리 끊김 — PX4 offboard 상실 페일세이프로 전환 예상"))
                continue
            if not self.enabled:
                # 'h'(전체 HOLD) 상태: 미션 복귀 명령을 보내지 않고 손만 뗀다 (HOLD 유지)
                o.owned = False
                continue

            if not o.owned:
                if risk[d.id] >= 1 and self.eligible(d):
                    o.owned, o.t_take, o.t_clear, o.hold_u = True, t, None, d.u
                    o.takeovers += 1
                    v = self._velocity(d, drones, risk[d.id])
                    cmds.append(("takeover", d.id, v))
                continue

            # owned
            if clear_all[d.id] and risk[d.id] == 0:
                if o.t_clear is None:
                    o.t_clear = t
            else:
                o.t_clear = None
            # 회피 중 '통과' 웨이포인트에 도달 → 미션에 넘겨 다음 웨이포인트로 진행 (PX4는 Offboard 중 미션 진행 안 함)
            #   정지 지점(대기·hold)이면 넘기지 않고 그 자리에서 회피만 하며 위험 해소를 기다린다 (모드 왕복 방지)
            if d.goal is not None and not d.goal_hold and risk[d.id] < 2 and \
                    _norm(d.goal[0] - d.f, d.goal[1] - d.r) < C.GOAL_HANDOFF and t - o.t_take >= 1.0:
                o.owned = False
                o.t_handoff = t
                cmds.append(("release", d.id, None))
                continue
            if o.t_clear is not None and t - o.t_clear >= C.RELEASE_HOLD and t - o.t_take >= C.MIN_OWN_TIME:
                o.owned = False
                cmds.append(("release", d.id, None))
                continue
            cmds.append(("vel", d.id, self._velocity(d, drones, risk[d.id])))
        return cmds

    def _velocity(self, d: DroneIn, drones: List[DroneIn], level: int):
        o = self.own[d.id]
        goal = d.goal
        if goal is None:
            sp = _norm(d.vf, d.vr)
            goal = (d.f + 10 * d.vf / sp, d.r + 10 * d.vr / sp) if sp > 0.3 else (d.f, d.r)
        others = [x for x in drones if x.id != d.id and x.in_air]
        emerg = level >= 2
        # 같은 지점으로 합류하는 경우: 우선순위 낮은 기체가 양보(제자리 대기) → 순서대로 통과
        o.yielding = False
        if d.goal is not None:
            for x in others:
                if x.prio < d.prio and x.fresh and x.goal is not None and abs(x.u - d.u) <= C.V_SEP \
                        and _norm(x.goal[0] - d.goal[0], x.goal[1] - d.goal[1]) < C.D_SAFE \
                        and _norm(x.f - d.f, x.r - d.r) < 3 * C.D_SAFE:
                    goal = (d.f, d.r)
                    o.yielding = True
                    break
        vf, vr, dbg = acact_velocity(d, others, goal, emergency=emerg)
        # 고도: 기본은 개입 시점 고도 유지. 긴급 시 우선순위 낮은 쪽만 상승.
        target_u = o.hold_u
        if emerg:
            lower = False
            for x in others:
                if abs(x.u - d.u) <= C.V_SEP and _norm(x.f - d.f, x.r - d.r) < C.D_EMERG + 2.0 \
                        and x.prio < d.prio:
                    lower = True
            if lower:
                target_u = min(d.u + 2.0, o.hold_u + C.EMERG_CLIMB_MAX)
                o.hold_u = max(o.hold_u, min(d.u, o.hold_u + C.EMERG_CLIMB_MAX))
        vu = max(-C.MAX_CLIMB, min(C.MAX_CLIMB, C.ALT_HOLD_KP * (target_u - d.u)))
        return (vf, vr, vu)
