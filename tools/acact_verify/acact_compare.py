#!/usr/bin/env python3
"""
acact_compare.py — ACACT 원본(Python, 수정1) ↔ C++ 이식 엔진 비교 검증
════════════════════════════════════════════════════════════════
원본 sim_check.py(오프라인 시뮬레이터)를 그대로 돌리되 GuardCore 자리에
'원본 core.py + C++ 엔진을 동시에 돌리는 비교 코어'를 끼운다.

  1) 동시 실행(lockstep): 매 스텝 같은 입력을 두 엔진에 넣고
     명령(종류·기체·속도·이벤트 문구), 쌍 평가(위험 수준·거리·CPA), 기체별 상태(개입·잠금·양보·개입 횟수)를 비교
  2) 폐루프 결과: C++ 엔진만으로 시뮬레이터를 돌려 원본과 결과표(최소 이격·개입 횟수·착륙)가 같은지 비교

사용:
  python3 acact_compare.py --lib build/libacact_capi.so            # 기본 묶음
  python3 acact_compare.py --lib ... --full                         # 시드·조건 확대
결과: 표준출력 요약 + --json 경로에 상세. 불일치가 하나라도 있으면 종료 코드 1.
"""
import argparse
import ctypes
import importlib
import json
import math
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REF = os.path.join(HERE, "..", "..", "vendor", "acact_guard", "rev1")
TOL = 1e-9


class AcDrone(ctypes.Structure):
    _fields_ = [("id", ctypes.c_char * 8), ("prio", ctypes.c_int), ("fresh", ctypes.c_int), ("age", ctypes.c_double),
                ("f", ctypes.c_double), ("r", ctypes.c_double), ("u", ctypes.c_double),
                ("vf", ctypes.c_double), ("vr", ctypes.c_double), ("vu", ctypes.c_double),
                ("rel_alt", ctypes.c_double), ("in_air", ctypes.c_int), ("mode", ctypes.c_char * 16),
                ("has_goal", ctypes.c_int), ("gf", ctypes.c_double), ("gr", ctypes.c_double),
                ("rtl_alt", ctypes.c_double), ("goal_hold", ctypes.c_int),
                ("has_goal_alt", ctypes.c_int), ("goal_alt", ctypes.c_double),
                ("has_home", ctypes.c_int), ("hf", ctypes.c_double), ("hr", ctypes.c_double)]


def load_ref(drones, profile):
    """원본 모듈을 기체 조합·프로파일에 맞게 새로 import (config 는 import 시점에 --drones 를 읽음)"""
    for m in ["config", "core", "scenarios", "sim_check", "geo"]:
        sys.modules.pop(m, None)
    os.environ["ACACT_DRONES"] = drones
    os.environ["ACACT_PROFILE"] = profile
    saved = list(sys.argv)
    sys.argv = [sys.argv[0]]
    if REF not in sys.path:
        sys.path.insert(0, REF)
    try:
        C = importlib.import_module("config")
        C.PROFILE = profile
        core = importlib.import_module("core")
        sim = importlib.import_module("sim_check")
    finally:
        sys.argv = saved
    return C, core, sim


def cfg_vector(C):
    a = C.ACACT
    return [C.STALE_PREDICT_MAX, C.DL_LOSS_T, C.STALE_DROP_T, C.DEGRADED_MARGIN, C.D_SAFE, C.D_EMERG, C.T_LOOK,
            C.V_SEP, C.RELEASE_MARGIN, C.RELEASE_HOLD, C.MIN_OWN_TIME, C.MIN_TAKEOVER_ALT, C.GOAL_HANDOFF,
            C.MAX_H_SPEED, C.MAX_CLIMB, C.EMERG_CLIMB_MAX, C.ALT_HOLD_KP, C.PAD_ZONE, C.SCENARIO_SPEED,
            1.0 if C.ADVANCE_IN_AVOID else 0.0,
            a["kpa"], a["kpp"], a["kpv"], a["rs"], a["ts"], a["k_rh"], a["k_cpa"], a["goal_tol"]]


class CppOwn:
    def __init__(self, v):
        self.owned, self.lock, self.yielding = bool(v[0]), bool(v[1]), bool(v[2])
        self.takeovers, self.owned_time, self.hold_u, self.t_take = int(v[3]), v[4], v[5], v[6]
        self.t_clear = v[8] if v[7] else None


class CppCore:
    """core.GuardCore 와 같은 모양의 C++ 엔진 래퍼"""
    def __init__(self, lib, C, ids):
        self.lib, self.ids = lib, list(ids)
        vec = cfg_vector(C)
        arr = (ctypes.c_double * len(vec))(*vec)
        self.h = lib.acact_new(",".join(ids).encode(), arr, len(vec))
        if not self.h:
            raise RuntimeError("acact_new 실패 (설정 개수 불일치)")
        self.buf = ctypes.create_string_buffer(1 << 16)

    def __del__(self):
        try:
            self.lib.acact_free(self.h)
        except Exception:
            pass

    @property
    def enabled(self):
        return True

    @enabled.setter
    def enabled(self, v):
        self.lib.acact_set_enabled(self.h, 1 if v else 0)

    def step(self, t, ins):
        arr = (AcDrone * max(1, len(ins)))()
        for i, d in enumerate(ins):
            a = arr[i]
            a.id = d.id.encode(); a.prio = d.prio; a.fresh = 1 if d.fresh else 0; a.age = d.age
            a.f, a.r, a.u, a.vf, a.vr, a.vu = d.f, d.r, d.u, d.vf, d.vr, d.vu
            a.rel_alt = d.rel_alt; a.in_air = 1 if d.in_air else 0; a.mode = d.mode.encode()
            if d.goal is not None:
                a.has_goal, a.gf, a.gr = 1, d.goal[0], d.goal[1]
            a.rtl_alt = d.rtl_alt; a.goal_hold = 1 if d.goal_hold else 0
            if d.goal_alt is not None:
                a.has_goal_alt, a.goal_alt = 1, d.goal_alt
            if d.home is not None:
                a.has_home, a.hf, a.hr = 1, d.home[0], d.home[1]
        n = self.lib.acact_step(self.h, ctypes.c_double(t), arr, len(ins), self.buf, len(self.buf))
        if n < 0:
            self.buf = ctypes.create_string_buffer(-n + 1024)
            raise RuntimeError("명령 버퍼 부족")
        out = []
        for line in self.buf.value.decode().splitlines():
            k, did, v0, v1, v2, text = line.split("\t", 5)
            if k == "event":
                out.append((k, did, text))
            elif k in ("takeover", "vel"):
                out.append((k, did, (float(v0), float(v1), float(v2))))
            else:
                out.append((k, did, None))
        return out

    @property
    def own(self):
        res = {}
        v = (ctypes.c_double * 9)()
        for i in self.ids:
            if self.lib.acact_own(self.h, i.encode(), v):
                res[i] = CppOwn(list(v))
        return res

    def pair_list(self):
        n = self.lib.acact_pairs(self.h, self.buf, len(self.buf))
        rows = []
        for line in self.buf.value.decode().splitlines():
            a, b, lv, dn, dc, tc, dz, cl, ms, m3 = line.split("\t")
            rows.append(((a, b), int(lv), float(dn), float(dc), float(tc), float(dz), cl == "1", float(ms), float(m3)))
        return rows


class Stats:
    def __init__(self):
        self.steps = 0
        self.cmds = 0
        self.max_vdiff = 0.0
        self.max_pdiff = 0.0
        self.mismatch = []

    def bad(self, where, msg):
        if len(self.mismatch) < 20:
            self.mismatch.append(f"{where}: {msg}")


class DualCore:
    """원본과 C++ 를 매 스텝 같은 입력으로 돌려 비교하고, 원본의 명령으로 시뮬레이터를 진행"""
    def __init__(self, core_mod, lib, C, ids, stats, tag):
        self.py = core_mod.GuardCore(ids)
        self.cpp = CppCore(lib, C, ids)
        self.st, self.tag = stats, tag

    @property
    def own(self):
        return self.py.own

    def step(self, t, ins):
        a = self.py.step(t, ins)
        b = self.cpp.step(t, ins)
        st = self.st
        st.steps += 1
        st.cmds += len(a)
        where = f"{self.tag} t={t:.2f}"
        if len(a) != len(b):
            st.bad(where, f"명령 수 {len(a)} ≠ {len(b)}  py={[(x[0], x[1]) for x in a]} cpp={[(x[0], x[1]) for x in b]}")
        else:
            for x, y in zip(a, b):
                if x[0] != y[0] or x[1] != y[1]:
                    st.bad(where, f"명령 {x[0]} {x[1]} ≠ {y[0]} {y[1]}")
                elif x[0] == "event" and x[2] != y[2]:
                    st.bad(where, f"이벤트 문구 '{x[2]}' ≠ '{y[2]}'")
                elif x[0] in ("takeover", "vel"):
                    dv = max(abs(p - q) for p, q in zip(x[2], y[2]))
                    st.max_vdiff = max(st.max_vdiff, dv)
                    if dv > TOL:
                        st.bad(where, f"{x[0]} {x[1]} 속도 차 {dv:.3e}")
        # 쌍 평가
        pp = list(self.py.pairs.items())
        cp = self.cpp.pair_list()
        if len(pp) != len(cp):
            st.bad(where, f"쌍 수 {len(pp)} ≠ {len(cp)}")
        else:
            for (k, pe), row in zip(pp, cp):
                if k != row[0] or pe.level != row[1] or pe.clear != row[6]:
                    st.bad(where, f"쌍 {k} 수준/해제 {pe.level}/{pe.clear} ≠ {row[1]}/{row[6]}")
                    continue
                for pv, cv in ((pe.d_now, row[2]), (pe.d_cpa, row[3]), (pe.t_cpa, row[4]), (pe.dz, row[5]),
                               (self.py.min_sep.get(k, 1e9), row[7]), (self.py.min_3d.get(k, 1e9), row[8])):
                    st.max_pdiff = max(st.max_pdiff, abs(pv - cv))
                    if abs(pv - cv) > TOL:
                        st.bad(where, f"쌍 {k} 값 {pv} ≠ {cv}")
        # 기체 상태
        co = self.cpp.own
        for i, o in self.py.own.items():
            c = co[i]
            if (o.owned, o.lock, o.yielding, o.takeovers) != (c.owned, c.lock, c.yielding, c.takeovers) \
                    or abs(o.owned_time - c.owned_time) > 1e-6 or abs(o.hold_u - c.hold_u) > TOL \
                    or (o.t_clear is None) != (c.t_clear is None):
                st.bad(where, f"{i} 상태 owned/lock/yield/n {o.owned}/{o.lock}/{o.yielding}/{o.takeovers} ≠ "
                              f"{c.owned}/{c.lock}/{c.yielding}/{c.takeovers}")
        return a


def summarize(r):
    return {"min3d": round(r["min3d"], 9), "minh": round(r["minh_same_layer"], 9), "takeovers": r["takeovers"],
            "landed": r["all_landed"], "flight_time": round(r["flight_time"], 6),
            "owned_time": r["owned_time"]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lib", required=True)
    ap.add_argument("--full", action="store_true", help="시드·조건 확대")
    ap.add_argument("--json", default=None)
    a = ap.parse_args()
    lib = ctypes.CDLL(os.path.abspath(a.lib))
    lib.acact_new.restype = ctypes.c_void_p
    lib.acact_new.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_double), ctypes.c_int]
    lib.acact_free.argtypes = [ctypes.c_void_p]
    lib.acact_set_enabled.argtypes = [ctypes.c_void_p, ctypes.c_int]
    lib.acact_step.argtypes = [ctypes.c_void_p, ctypes.c_double, ctypes.c_void_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_int]
    lib.acact_own.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.POINTER(ctypes.c_double)]
    lib.acact_pairs.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]

    seeds = 6 if a.full else 2
    # (기체 조합, 프로파일, 시나리오 목록) — 시나리오 None = 해당 조합에서 가능한 전체
    sets = [("D1,D2", "oregon2", None), ("D1,D2,D3,D4", "oregon", None), ("D1,D3", "hwaseong", None)]
    if a.full:
        sets += [("D1,D2,D3,D4", "hwaseong", None), ("D1,D2", "hwaseong", None)]
    stress = [("기준", {}), ("GPS±3", {"gps": 3.0}), ("지연0.5+손실15%", {"lat": 0.5, "drop": 0.15}),
              ("전환지연1.0", {"sw": 1.0}), ("돌풍1.0", {"gust": 1.0}),
              ("복합", {"gps": 2.0, "lat": 0.3, "drop": 0.10, "sw": 0.6, "acc": 1.2, "gust": 0.6})]
    faults = [("S3_cross4", ("D1", 5.0)), ("S2_headon", ("D1", 6.0)), ("S6_linkloss", ("D2", 1.0)), ("S7_duo", ("D2", 4.0))]

    report = {"runs": [], "ok": True}
    st_all = Stats()
    t0 = time.time()
    for drones, profile, names in sets:
        C, core, sim = load_ref(drones, profile)
        SC = sys.modules["scenarios"]
        ids = SC.IDS
        names = names or [n for n in SC.SCENARIOS if SC.available(n)]
        conds = stress if (drones == "D1,D2" and profile == "oregon2") else [("기준", {})]
        for cname, cond in conds:
            sim.TELEM_LAT = cond.get("lat", 0.15); sim.TELEM_DROP = cond.get("drop", 0.0)
            sim.OB_SWITCH = cond.get("sw", 0.35); sim.ACC_H = cond.get("acc", 1.5); sim.GUST = cond.get("gust", 0.0)
            gps = cond.get("gps", 1.0)
            for name in names:
                if cname != "기준" and name != "S7_duo":
                    continue
                for mode in ("demo", "rehearsal"):
                    if cname != "기준" and mode != "demo":
                        continue
                    for seed in range(1, seeds + 1):
                        tag = f"{drones}/{profile}/{name}/{mode}/{cname}/s{seed}"
                        st = Stats()
                        orig = core.GuardCore
                        # 1) lockstep
                        sim.GuardCore = lambda ids_, _c=core, _C=C, _st=st, _tag=tag: DualCore(_c, lib, _C, ids_, _st, _tag)
                        r_dual = sim.run(name, mode, seed=seed, gps_err=gps, plot=False)
                        # 2) 원본만 / C++ 만 (폐루프 결과 비교)
                        sim.GuardCore = orig
                        r_py = sim.run(name, mode, seed=seed, gps_err=gps, plot=False)
                        sim.GuardCore = lambda ids_, _C=C: CppCore(lib, _C, ids_)
                        r_cpp = sim.run(name, mode, seed=seed, gps_err=gps, plot=False)
                        sim.GuardCore = orig
                        same = summarize(r_py) == summarize(r_cpp) == summarize(r_dual)
                        ok = same and not st.mismatch
                        report["ok"] &= ok
                        report["runs"].append({"tag": tag, "ok": ok, "steps": st.steps, "cmds": st.cmds,
                                               "max_vdiff": st.max_vdiff, "max_pdiff": st.max_pdiff,
                                               "py": summarize(r_py), "cpp": summarize(r_cpp),
                                               "mismatch": st.mismatch})
                        st_all.steps += st.steps; st_all.cmds += st.cmds
                        st_all.max_vdiff = max(st_all.max_vdiff, st.max_vdiff)
                        st_all.max_pdiff = max(st_all.max_pdiff, st.max_pdiff)
                        if not ok:
                            print(f"  불일치 {tag}: 결과 동일={same}")
                            for m in st.mismatch[:5]:
                                print("     ", m)
        # 고장 주입 (해당 조합에서 가능한 시나리오만)
        for name, fault in faults:
            if not SC.available(name) or fault[0] not in ids:
                continue
            sim.TELEM_LAT, sim.TELEM_DROP, sim.OB_SWITCH, sim.ACC_H, sim.GUST = 0.15, 0.0, 0.35, 1.5, 0.0
            for seed in range(1, seeds + 1):
                tag = f"{drones}/{profile}/{name}/demo/고장{fault[0]}@{fault[1]}/s{seed}"
                st = Stats()
                orig = core.GuardCore
                sim.GuardCore = lambda ids_, _c=core, _C=C, _st=st, _tag=tag: DualCore(_c, lib, _C, ids_, _st, _tag)
                r_dual = sim.run(name, "demo", seed=seed, fault=fault, plot=False)
                sim.GuardCore = orig
                r_py = sim.run(name, "demo", seed=seed, fault=fault, plot=False)
                sim.GuardCore = lambda ids_, _C=C: CppCore(lib, _C, ids_)
                r_cpp = sim.run(name, "demo", seed=seed, fault=fault, plot=False)
                sim.GuardCore = orig
                same = summarize(r_py) == summarize(r_cpp) == summarize(r_dual)
                ok = same and not st.mismatch
                report["ok"] &= ok
                report["runs"].append({"tag": tag, "ok": ok, "steps": st.steps, "cmds": st.cmds,
                                       "max_vdiff": st.max_vdiff, "max_pdiff": st.max_pdiff,
                                       "py": summarize(r_py), "cpp": summarize(r_cpp), "mismatch": st.mismatch})
                st_all.steps += st.steps; st_all.cmds += st.cmds
                st_all.max_vdiff = max(st_all.max_vdiff, st.max_vdiff)
                st_all.max_pdiff = max(st_all.max_pdiff, st.max_pdiff)
                if not ok:
                    print(f"  불일치 {tag}: 결과 동일={same}")
                    for m in st.mismatch[:5]:
                        print("     ", m)

    n_ok = sum(1 for r in report["runs"] if r["ok"])
    report["summary"] = {"runs": len(report["runs"]), "ok": n_ok, "steps": st_all.steps, "commands": st_all.cmds,
                         "max_velocity_diff": st_all.max_vdiff, "max_pair_value_diff": st_all.max_pdiff,
                         "seconds": round(time.time() - t0, 1)}
    print(json.dumps(report["summary"], ensure_ascii=False))
    print("결과:", "모두 일치" if report["ok"] else "불일치 있음")
    if a.json:
        with open(a.json, "w", encoding="utf-8") as f:
            json.dump(report, f, ensure_ascii=False, indent=1)
    sys.exit(0 if report["ok"] else 1)


if __name__ == "__main__":
    main()
