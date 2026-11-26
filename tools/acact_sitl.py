#!/usr/bin/env python3
"""
acact_sitl.py — ACACT built into the GCS, flown against two PX4 SIH instances.

Setup (this script, over each vehicle's onboard link 14540+i):
  - two quadcopters 40 m apart (spawn set by ci_sitl.sh)
  - head-on missions at the same altitude (8 m):
      D1: takeoff → wait point W (LOITER_UNLIM) → fly to E → wait point → land
      D2: takeoff → wait point E (LOITER_UNLIM) → fly to W → wait point → land
    i.e. after the synchronised start both cross the same line in opposite
    directions; without avoidance they would meet nose to nose.
Everything else is done by the GCS (ML_TEST_ACACT=1): it starts its guard,
runs the preflight, arms and starts both vehicles one after the other
(highest id first), advances the wait points itself (auto-advance), and must
avoid the collision on its own.

Checks:
  both_airborne       both climbed above 6 m
  takeover            at least one vehicle went to OFFBOARD (guard took over)
  separation          minimum horizontal distance while both airborne and at the same
                      layer (|dz| < 4 m) >= 5.5 m (D_EMERG)  — the guard's own bound
  returned            every vehicle that the guard took over went back to MISSION
  completed           both landed and disarmed at the far side
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
ALT = 8.0
LEG = 40.0          # W ↔ E distance [m]


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
                self.seq = m.seq
            elif t == "STATUSTEXT":
                log(self.name, "PX4:", m.text)

    def upload(self, items):
        c = self.c
        c.mav.mission_clear_all_send(c.target_system, c.target_component)
        time.sleep(0.5)
        c.mav.mission_count_send(c.target_system, c.target_component, len(items), 0)
        end = time.time() + 30
        while time.time() < end:
            m = c.recv_match(type=["MISSION_REQUEST_INT", "MISSION_REQUEST", "MISSION_ACK"], blocking=True, timeout=1)
            if m is None:
                continue
            if m.get_type() == "MISSION_ACK":
                log(self.name, "mission ack", m.type)
                return m.type == 0
            cmd, lat, lon, alt = items[m.seq]
            frame = mav.MAV_FRAME_MISSION if cmd in (mav.MAV_CMD_NAV_LAND,) and lat == 0 else mav.MAV_FRAME_GLOBAL_RELATIVE_ALT_INT
            c.mav.mission_item_int_send(c.target_system, c.target_component, m.seq, frame, cmd, 0, 1,
                                        0, 0, 0, float("nan"), int(lat * 1e7), int(lon * 1e7), alt, 0)
        return False


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
    if sep0 < 20:
        res["notes"].append(f"spawn positions too close ({sep0:.1f} m) — PX4_PARAM_SIH_LOC_* not applied?")
        finish(2)

    # head-on missions: W = 20 m north of D1, E = 20 m north of D2
    W = offset(vs[0].lat, vs[0].lon, 20, 0)
    E = offset(vs[1].lat, vs[1].lon, 20, 0)
    TK, WP, LU, LD = mav.MAV_CMD_NAV_TAKEOFF, mav.MAV_CMD_NAV_WAYPOINT, mav.MAV_CMD_NAV_LOITER_UNLIM, mav.MAV_CMD_NAV_LAND
    plans = [
        [(TK, vs[0].lat, vs[0].lon, ALT), (LU, W[0], W[1], ALT), (WP, E[0], E[1], ALT), (LU, E[0], E[1], ALT), (LD, E[0], E[1], 0)],
        [(TK, vs[1].lat, vs[1].lon, ALT), (LU, E[0], E[1], ALT), (WP, W[0], W[1], ALT), (LU, W[0], W[1], ALT), (LD, W[0], W[1], 0)],
    ]
    # D2 lands at W, D1 at E — keep the landing points apart from each other's track ends
    plans[0][-2] = (LU, *offset(E[0], E[1], 0, 12), ALT)
    plans[0][-1] = (LD, *offset(E[0], E[1], 0, 12), 0)
    plans[1][-2] = (LU, *offset(W[0], W[1], 0, -12), ALT)
    plans[1][-1] = (LD, *offset(W[0], W[1], 0, -12), 0)
    for v, p in zip(vs, plans):
        if not v.upload(p):
            res["notes"].append(f"{v.name}: mission upload failed")
            finish(2)
    log("missions uploaded; the GCS takes it from here")

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
        done = len(airborne) == 2 and all(not v.armed for v in vs)
        if done:
            break
        time.sleep(0.05)

    res["metrics"].update({"min_horizontal_same_layer_m": round(min_h, 2) if min_h < 1e8 else None, "min_at_s": min_t,
                           "takeovers": sorted(took), "returned": sorted(returned),
                           "modes": {v.name: v.modes_seen for v in vs}, "max_alt": {v.name: round(v.max_alt, 1) for v in vs}})
    res["checks"] = {
        "both_airborne": len(airborne) == 2,
        "takeover": len(took) >= 1,
        "separation": min_h >= 5.5,
        "returned": len(took) >= 1 and took == returned,
        "completed": len(airborne) == 2 and all(not v.armed for v in vs),
    }
    finish(0 if all(res["checks"].values()) else 1)


if __name__ == "__main__":
    main()
