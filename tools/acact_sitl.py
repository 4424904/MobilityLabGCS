#!/usr/bin/env python3
"""
acact_sitl.py — ACACT built into the GCS, flown against two PX4 SIH instances (passive checker).

The GCS does everything itself (ML_TEST_ACACT=1), exactly the guard.py rev1 operator workflow:
  site from the vehicles (bearing auto = mean heading, oregon layout) → load S7_duo demo
  (scenarios.py built by the C++ engine, uploaded and read back by the GCS) → guard start → preflight
  → sequential arm/start → auto-advance through every sync point → land.
This script only listens on each vehicle's onboard link (14540+i) and checks the outcome.

Checks:
  mission_loaded      both vehicles report a mission (MISSION_CURRENT total > 5) — uploaded by the GCS
  both_airborne       both climbed above 6 m
  advanced            both went through ≥ 3 sync points (mission sequence advanced by the GCS)
  takeover            at least one vehicle went to OFFBOARD (guard took over)
  separation          minimum horizontal distance while both airborne at the same layer (|dz| < 4 m)
                      >= 5.5 m (D_EMERG)
  returned            every vehicle the guard took over went back to MISSION
  completed           both landed and disarmed
Result: sitl-acact.json
"""
import argparse
import json
import math
import os
import sys
import time

from pymavlink import mavutil

mav = mavutil.mavlink


def log(*a):
    print(f"[{time.strftime('%H:%M:%S')}]", *a, flush=True)


def offset(lat, lon, dn, de):
    return lat + dn / 111320.0, lon + de / (111320.0 * math.cos(math.radians(lat)))


def dist_m(a, b):
    dn = (a[0] - b[0]) * 111320.0
    de = (a[1] - b[1]) * 111320.0 * math.cos(math.radians(a[0]))
    return math.hypot(dn, de)


PX4_MODES = {(4, 4): "MISSION", (4, 3): "HOLD", (4, 5): "RTL", (4, 6): "LAND", (4, 2): "TAKEOFF", (6, 0): "OFFBOARD"}


class V:
    def __init__(self, name, port):
        self.name = name
        self.c = mavutil.mavlink_connection(f"udpin:0.0.0.0:{port}", source_system=250, source_component=191, dialect="common")
        self.lat = self.lon = None
        self.alt = 0.0
        self.mode = "?"
        self.armed = False
        self.landed = None
        self.seq = -1
        self.modes_seen = []
        self.max_alt = 0.0
        self.seqs = []
        self.total = 0

    def pump(self):
        while True:
            m = self.c.recv_match(blocking=False)
            if m is None:
                return
            t = m.get_type()
            if t == "HEARTBEAT" and m.get_srcComponent() == 1 and m.type != mav.MAV_TYPE_GCS:
                self.armed = bool(m.base_mode & mav.MAV_MODE_FLAG_SAFETY_ARMED)
                main = (m.custom_mode >> 16) & 0xFF
                sub = (m.custom_mode >> 24) & 0xFF
                mode = PX4_MODES.get((main, sub if main == 4 else 0), f"{main}/{sub}")
                if mode != self.mode:
                    self.mode = mode
                    self.modes_seen.append((round(time.time(), 1), mode))
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--timeout", type=float, default=600)
    a = ap.parse_args()
    res = {"fw": "px4-acact", "checks": {}, "notes": [], "metrics": {}}

    def finish(code):
        with open(os.path.join(a.out, "sitl-acact.json"), "w") as f:
            json.dump(res, f, indent=2, ensure_ascii=False)
        log("RESULT", json.dumps(res["checks"]), json.dumps(res["metrics"]))
        sys.exit(code)

    vs = [V("D1", 14540), V("D2", 14541)]
    for v in vs:
        log("waiting for", v.name)
        if not v.c.wait_heartbeat(timeout=180):
            res["notes"].append(f"{v.name}: no heartbeat")
            finish(2)
        log(v.name, "system", v.c.target_system)
    # positions + GPS
    end = time.time() + 180
    while time.time() < end and any(v.lat is None for v in vs):
        for v in vs:
            v.pump()
        time.sleep(0.1)
    if any(v.lat is None for v in vs):
        res["notes"].append("no position")
        finish(2)
    time.sleep(8)
    for v in vs:
        v.pump()
    sep0 = dist_m((vs[0].lat, vs[0].lon), (vs[1].lat, vs[1].lon))
    log("spawn separation", round(sep0, 1), "m")
    res["metrics"]["spawn_separation_m"] = round(sep0, 1)
    log("the GCS takes it from here (site, S7_duo upload, guard, start, auto-advance)")

    t0 = time.time()
    min_h = 1e9
    min_t = None
    took = set()
    returned = set()
    airborne = set()
    while time.time() - t0 < a.timeout:
        for v in vs:
            v.pump()
            if v.alt > 6:
                airborne.add(v.name)
            if v.mode == "OFFBOARD":
                took.add(v.name)
            if v.name in took and v.mode == "MISSION":
                returned.add(v.name)
        if all(v.lat is not None for v in vs) and all(v.alt > 3 for v in vs) and abs(vs[0].alt - vs[1].alt) < 4.0:
            d = dist_m((vs[0].lat, vs[0].lon), (vs[1].lat, vs[1].lon))
            if d < min_h:
                min_h, min_t = d, round(time.time() - t0, 1)
        done = len(airborne) == 2 and all(not v.armed and v.landed in (None, 1) for v in vs)
        if done:
            break
        time.sleep(0.05)

    res["metrics"].update({"min_horizontal_same_layer_m": round(min_h, 2) if min_h < 1e8 else None, "min_at_s": min_t,
                           "takeovers": sorted(took), "returned": sorted(returned),
                           "mission_total": {v.name: v.total for v in vs}, "seq_history": {v.name: v.seqs for v in vs},
                           "modes": {v.name: v.modes_seen for v in vs}, "max_alt": {v.name: round(v.max_alt, 1) for v in vs}})
    res["checks"] = {
        "mission_loaded": all(v.total > 5 for v in vs),
        "both_airborne": len(airborne) == 2,
        "advanced": all(len(set(v.seqs)) >= 6 for v in vs),
        "takeover": len(took) >= 1,
        "separation": min_h >= 5.5,
        "returned": len(took) >= 1 and took == returned,
        "completed": len(airborne) == 2 and all(not v.armed for v in vs),
    }
    finish(0 if all(res["checks"].values()) else 1)


if __name__ == "__main__":
    main()
