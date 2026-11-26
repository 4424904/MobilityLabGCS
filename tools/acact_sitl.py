#!/usr/bin/env python3
"""
acact_sitl.py — checker for the ACACT SITL cases (two PX4 SIH quadcopters, GCS with the built-in guard).

The GCS does the operator's work itself (custom/qml/MobilityLab/Controls/MLAcactTestDriver.qml);
this script only listens on each vehicle's onboard link (udp 14540+i), reads the GCS log and
marker files written by tools/ci_sitl.sh, and judges the outcome.

  --make-plans DIR   write the user-mission .plan files (D1, D2, D2_bad) for the spawn points and exit

Cases and checks (all cases: no two airborne vehicles at the same layer closer than D_EMERG 5.5 m)
  s7duo      mission_loaded, both_airborne, advanced (sync points), takeover, returned, completed
  preflight  load_refused_without_site, heading_issue, start_blocked, never_armed
  user       bad_mission_blocked (TAKEOFF_FAR → start refused), check_warns_crossing (PATH_NEAR, no error),
             both_airborne, takeover, returned, completed
  gcskill    killed_during_avoidance, offboard_failsafe (every vehicle in OFFBOARD at the kill leaves OFFBOARD
             within 3 s — PX4 offboard-loss failsafe, no GCS needed), restart_no_takeover (restarted GCS
             does not take hovering vehicles), completed (operator resumes after restart)
  linkloss   link_cut_during_avoidance, gcs_marked_lost, cut_vehicle_safe (if it was being flown it left
             OFFBOARD within 3 s; else it kept flying its mission), completed
  operator   operator_hold (D1 HOLD after the operator command), not_retaken (no OFFBOARD on D1 until its
             mission was resumed), returned, completed
Result: sitl-acact-<case>.json
"""
import argparse
import json
import math
import os
import re
import sys
import time

from pymavlink import mavutil

mav = mavutil.mavlink
D_EMERG = 5.5
V_SEP = 4.0

# spawn points (tools/ci_sitl.sh): oregon layout, bearing 0, D2 15 m east of D1
SPAWN = {"D1": (37.2100856, 126.8307462), "D2": (37.2100856, 126.8309154)}


def log(*a):
    print(f"[{time.strftime('%H:%M:%S')}]", *a, flush=True)


def offset(lat, lon, dn, de):
    return lat + dn / 111320.0, lon + de / (111320.0 * math.cos(math.radians(lat)))


def dist_m(a, b):
    dn = (a[0] - b[0]) * 111320.0
    de = (a[1] - b[1]) * 111320.0 * math.cos(math.radians(a[0]))
    return math.hypot(dn, de)


# ---- user missions ---------------------------------------------------------------
def plan(home, items):
    out = []
    for k, (cmd, lat, lon, alt, p1) in enumerate(items):
        out.append({"type": "SimpleItem", "command": cmd, "frame": 3, "autoContinue": True, "doJumpId": k + 1,
                    "params": [p1, 0, 0, None, lat, lon, alt], "Altitude": alt, "AltitudeMode": 1, "AMSLAltAboveTerrain": None})
    return {"fileType": "Plan", "groundStation": "QGroundControl", "version": 1,
            "mission": {"version": 2, "firmwareType": 12, "vehicleType": 2, "cruiseSpeed": 15, "hoverSpeed": 3,
                        "globalPlanAltitudeMode": 1, "plannedHomePosition": [home[0], home[1], 0], "items": out},
            "geoFence": {"version": 2, "circles": [], "polygons": []},
            "rallyPoints": {"version": 2, "points": []}}


def make_plans(d):
    """Crossing X at 10 m: D1 (0,0)→(40,15), D2 (0,15)→(40,0). D2 starts first (start order D2→D1, 5 s apart)
    so it waits 5 s over its pad to meet D1 in the middle. Landing points 29 m apart."""
    os.makedirs(d, exist_ok=True)
    a, b = SPAWN["D1"], SPAWN["D2"]
    TK, WP, LD = 22, 16, 21
    p = lambda base, n, e: offset(base[0], base[1], n, e)
    d1 = [(TK, *a, 10, 0), (WP, *p(a, 40, 15), 10, 0), (LD, *p(a, 40, 22), 0, 0)]
    d2 = [(TK, *b, 10, 0), (WP, *b, 10, 5), (WP, *p(b, 40, -15), 10, 0), (LD, *p(b, 40, -22), 0, 0)]
    bad = list(d2)
    bad[0] = (TK, *p(b, 30, 0), 10, 0)   # takeoff point 30 m away: someone else's mission
    for name, home, items in (("D1", a, d1), ("D2", b, d2), ("D2_bad", b, bad)):
        with open(os.path.join(d, name + ".plan"), "w") as f:
            json.dump(plan(home, items), f, indent=1)
    log("plans written to", d)


# ---- vehicles ---------------------------------------------------------------------
PX4_MODES = {(4, 4): "MISSION", (4, 3): "HOLD", (4, 5): "RTL", (4, 6): "LAND", (4, 2): "TAKEOFF", (6, 0): "OFFBOARD"}


class V:
    def __init__(self, name, port):
        self.name = name
        self.c = mavutil.mavlink_connection(f"udpin:0.0.0.0:{port}", source_system=250, source_component=191, dialect="common")
        self.lat = self.lon = None
        self.alt = 0.0
        self.mode = "?"
        self.armed = False
        self.ever_armed = False
        self.landed = None
        self.seq = -1
        self.seqs = []
        self.total = 0
        self.modes = []          # (t, mode)
        self.max_alt = 0.0

    def pump(self):
        while True:
            m = self.c.recv_match(blocking=False)
            if m is None:
                return
            t = m.get_type()
            if t == "HEARTBEAT" and m.get_srcComponent() == 1 and m.type != mav.MAV_TYPE_GCS:
                self.armed = bool(m.base_mode & mav.MAV_MODE_FLAG_SAFETY_ARMED)
                self.ever_armed |= self.armed
                main = (m.custom_mode >> 16) & 0xFF
                sub = (m.custom_mode >> 24) & 0xFF
                mode = PX4_MODES.get((main, sub if main == 4 else 0), f"{main}/{sub}")
                if mode != self.mode:
                    self.mode = mode
                    self.modes.append((time.time(), mode))
                    log(self.name, "mode →", mode)
            elif t == "GLOBAL_POSITION_INT":
                self.lat, self.lon, self.alt = m.lat / 1e7, m.lon / 1e7, m.relative_alt / 1000.0
                self.max_alt = max(self.max_alt, self.alt)
            elif t == "EXTENDED_SYS_STATE":
                self.landed = m.landed_state
            elif t == "MISSION_CURRENT":
                if m.seq != self.seq:
                    self.seqs.append(m.seq)
                self.seq = m.seq
                self.total = getattr(m, "total", 0) or self.total
            elif t == "STATUSTEXT":
                log(self.name, "PX4:", m.text)

    def mode_at(self, t):
        cur = "?"
        for tm, md in self.modes:
            if tm <= t:
                cur = md
        return cur

    def first_change_after(self, t, frm):
        for tm, md in self.modes:
            if tm > t and md != frm:
                return tm, md
        return None, None


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def marker(out, name):
    s = read(os.path.join(out, name)).strip()
    return float(s) if s else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out")
    ap.add_argument("--case", default="s7duo")
    ap.add_argument("--app-log", default="")
    ap.add_argument("--timeout", type=float, default=1200)
    ap.add_argument("--make-plans")
    a = ap.parse_args()
    if a.make_plans:
        make_plans(a.make_plans)
        return
    res = {"case": a.case, "checks": {}, "notes": [], "metrics": {}}

    def finish(code):
        with open(os.path.join(a.out, f"sitl-acact-{a.case}.json"), "w") as f:
            json.dump(res, f, indent=2, ensure_ascii=False)
        log("RESULT", a.case, json.dumps(res["checks"]), json.dumps({k: v for k, v in res["metrics"].items() if k != "modes"}))
        sys.exit(code)

    vs = [V("D1", 14540), V("D2", 14541)]
    for v in vs:
        log("waiting for", v.name)
        if not v.c.wait_heartbeat(timeout=180):
            res["notes"].append(f"{v.name}: no heartbeat")
            finish(2)
    end = time.time() + 180
    while time.time() < end and any(v.lat is None for v in vs):
        for v in vs:
            v.pump()
        time.sleep(0.1)
    if any(v.lat is None for v in vs):
        res["notes"].append("no position")
        finish(2)
    res["metrics"]["spawn_separation_m"] = round(dist_m((vs[0].lat, vs[0].lon), (vs[1].lat, vs[1].lon)), 1)
    log("the GCS takes it from here, case", a.case)

    t0 = time.time()
    min_h, min_t = 1e9, None
    airborne = set()
    app = ""
    timeout = 240 if a.case == "preflight" else a.timeout
    while time.time() - t0 < timeout:
        for v in vs:
            v.pump()
            if v.alt > 6:
                airborne.add(v.name)
        if all(v.lat is not None for v in vs) and all(v.alt > 2 for v in vs) and abs(vs[0].alt - vs[1].alt) < V_SEP:
            d = dist_m((vs[0].lat, vs[0].lon), (vs[1].lat, vs[1].lon))
            if d < min_h:
                min_h, min_t = d, round(time.time() - t0, 1)
        if a.case == "preflight":
            app = read(a.app_log)
            if "MLACACT test: done" in app and time.time() - t0 > 60:
                break
        elif len(airborne) == 2 and all(not v.armed and v.landed in (None, 1) for v in vs):
            break
        time.sleep(0.05)
    app = read(a.app_log)
    tl = lambda pat: re.search(pat, app) is not None

    took = {v.name for v in vs if any(m == "OFFBOARD" for _, m in v.modes)}
    returned = set()
    for v in vs:
        seen_off = False
        for _, m in v.modes:
            seen_off |= m == "OFFBOARD"
            if seen_off and m == "MISSION":
                returned.add(v.name)
    completed = len(airborne) == 2 and all(not v.armed for v in vs)
    res["metrics"].update({
        "min_horizontal_same_layer_m": round(min_h, 2) if min_h < 1e8 else None, "min_at_s": min_t,
        "takeovers": sorted(took), "returned": sorted(returned), "mission_total": {v.name: v.total for v in vs},
        "max_alt": {v.name: round(v.max_alt, 1) for v in vs},
        "modes": {v.name: [(round(t - t0, 1), m) for t, m in v.modes] for v in vs}})
    sep_ok = min_h >= D_EMERG
    C = res["checks"]

    if a.case == "s7duo":
        C.update({"mission_loaded": all(v.total > 5 for v in vs), "both_airborne": len(airborne) == 2,
                  "advanced": all(len(set(v.seqs)) >= 6 for v in vs), "takeover": len(took) >= 1,
                  "separation": sep_ok, "returned": len(took) >= 1 and took == returned, "completed": completed})
    elif a.case == "preflight":
        C.update({"load_refused_without_site": tl(r"load without site refused=true"),
                  "heading_issue": tl(r"heading issue=true"), "start_blocked": tl(r"start with wrong bearing=false"),
                  "never_armed": not any(v.ever_armed for v in vs)})
    elif a.case == "user":
        m = re.search(r"bad mission errors=(\d+) \[([^\]]*)\] start=(\w+)", app)
        k = re.search(r"mission check errors=(\d+) warnings=(\d+) \[([^\]]*)\]", app)
        C.update({"bad_mission_blocked": bool(m) and int(m.group(1)) > 0 and "TAKEOFF_FAR" in m.group(2) and m.group(3) == "false",
                  "check_warns_crossing": bool(k) and k.group(1) == "0" and "PATH_NEAR" in k.group(3),
                  "both_airborne": len(airborne) == 2, "takeover": len(took) >= 1, "separation": sep_ok,
                  "returned": len(took) >= 1 and took == returned, "completed": completed})
    elif a.case == "gcskill":
        tk, tr = marker(a.out, "gcs_killed_at"), marker(a.out, "gcs_restarted_at")
        res["metrics"]["killed_at_s"] = round(tk - t0, 1) if tk else None
        fs = {}
        for v in vs:
            if tk and v.mode_at(tk) == "OFFBOARD":
                tc, md = v.first_change_after(tk, "OFFBOARD")
                fs[v.name] = (round(tc - tk, 2), md) if tc else (None, None)
        res["metrics"]["failsafe_after_kill"] = fs
        retaken = any(m == "OFFBOARD" and tr and tr < t < tr + 12 for v in vs for t, m in v.modes)
        C.update({"killed_during_avoidance": bool(tk) and len(fs) >= 1,
                  "offboard_failsafe": len(fs) >= 1 and all(d is not None and d <= 3.0 for d, _ in fs.values()),
                  "restart_no_takeover": bool(tr) and not retaken,
                  "separation": sep_ok, "completed": completed})
    elif a.case == "linkloss":
        tc, tr = marker(a.out, "link_cut_at"), marker(a.out, "link_restored_at")
        d2 = vs[1]
        was_flown = tc is not None and d2.mode_at(tc) == "OFFBOARD"
        safe = False
        if tc:
            if was_flown:
                tch, md = d2.first_change_after(tc, "OFFBOARD")
                safe = tch is not None and tch - tc <= 3.0
                res["metrics"]["d2_failsafe"] = (round(tch - tc, 2), md) if tch else None
            else:
                safe = d2.mode_at(tc + 5) in ("MISSION", "HOLD", "LAND")
        res["metrics"].update({"cut_at_s": round(tc - t0, 1) if tc else None, "d2_flown_at_cut": was_flown})
        C.update({"link_cut_during_avoidance": bool(tc) and bool(tr),
                  "gcs_marked_lost": tl(r"MLACACT D2 \| .*(끊김|두절|상실)"),
                  "cut_vehicle_safe": safe, "separation": sep_ok, "completed": completed})
    elif a.case == "operator":
        d1 = vs[0]
        hold_t = None
        for i in range(1, len(d1.modes)):
            if d1.modes[i - 1][1] == "OFFBOARD" and d1.modes[i][1] == "HOLD":
                hold_t = d1.modes[i][0]
                break
        resume_t = next((t for t, m in d1.modes if hold_t and t > hold_t and m == "MISSION"), None)
        retaken = any(m == "OFFBOARD" and hold_t and t > hold_t and (resume_t is None or t < resume_t) for t, m in d1.modes)
        C.update({"operator_hold": tl(r"operator HOLD D1") and hold_t is not None,
                  "not_retaken": hold_t is not None and not retaken,
                  "resumed": resume_t is not None, "separation": sep_ok, "completed": completed})
    finish(0 if C and all(C.values()) else 1)


if __name__ == "__main__":
    main()
