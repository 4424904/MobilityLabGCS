#!/usr/bin/env python3
"""Fly a SITL vehicle through a mission and check it reacts to the GCS 목표 조정 commands.

The GCS (MobilityLabGCS with ML_TEST_SETPOINTS=1) talks to the SITL on its own
link and, once the mission is flying, sends: speed 2.5 m/s, altitude +15 m,
heading 225. This script sits on a second MAVLink link, prepares the vehicle
(mission upload, arm, start) and watches what the aircraft actually does:

  speed_in_mission   cruise drops to ~2.5 m/s while the mission keeps running
  altitude_change    after the mission pauses, the vehicle climbs ~15 m
  heading_change     the vehicle turns to ~225°

Results go to <out>/sitl-<fw>.json and a readable summary is printed.
"""
import argparse
import json
import math
import os
import struct
import sys
import time

os.environ.setdefault("MAVLINK20", "1")
from pymavlink import mavutil  # noqa: E402

mav = mavutil.mavlink

TEST_SPEED = 2.5
ALT_STEP = 15.0
TEST_HEADING = 225.0   # not a mission leg direction (legs run 090/000/270/180)
TAKEOFF_ALT = 20.0


def log(*a):
    print(f"[{time.strftime('%H:%M:%S')}]", *a, flush=True)


class Vehicle:
    def __init__(self, conn, fw):
        self.c = conn
        self.fw = fw
        self.hb = None
        self.alt = float("nan")
        self.gs = float("nan")
        self.hdg = float("nan")
        self.lat = self.lon = None
        self.armed = False
        self.fix = 0
        self.mode = ""
        self.statustext = []

    def pump(self, timeout=0.05):
        end = time.time() + timeout
        while True:
            m = self.c.recv_match(blocking=True, timeout=max(0.0, end - time.time()))
            if m is None:
                return
            t = m.get_type()
            if t == "HEARTBEAT" and m.get_srcComponent() == 1 and m.type != mav.MAV_TYPE_GCS:
                self.hb = m
                self.armed = bool(m.base_mode & mav.MAV_MODE_FLAG_SAFETY_ARMED)
                self.mode = self.c.flightmode or ""
            elif t == "GLOBAL_POSITION_INT":
                self.alt = m.relative_alt / 1000.0
                self.lat, self.lon = m.lat / 1e7, m.lon / 1e7
                self.hdg = m.hdg / 100.0 if m.hdg != 65535 else self.hdg
            elif t == "GPS_RAW_INT":
                self.fix = m.fix_type
            elif t == "VFR_HUD":
                self.gs = m.groundspeed
            elif t == "STATUSTEXT":
                self.statustext.append(m.text)
                log("  vehicle:", m.text)
            if time.time() >= end:
                return

    def wait(self, seconds):
        end = time.time() + seconds
        while time.time() < end:
            self.pump(0.2)

    def command(self, cmd, *params, retries=3):
        p = list(params) + [0] * (7 - len(params))
        for _ in range(retries):
            self.c.mav.command_long_send(self.c.target_system, self.c.target_component, cmd, 0, *p)
            end = time.time() + 3
            while time.time() < end:
                m = self.c.recv_match(type="COMMAND_ACK", blocking=True, timeout=0.5)
                if m and m.command == cmd:
                    return m.result
                self.pump(0.01)
        return None

    def set_mode(self, name):
        mapping = self.c.mode_mapping() or {}
        if name not in mapping:
            log("unknown mode", name, "known:", list(mapping)[:20])
            return False
        mode_id = mapping[name]
        if isinstance(mode_id, tuple):   # PX4: (base, main, sub)
            base, main, sub = mode_id
            self.c.mav.command_long_send(self.c.target_system, self.c.target_component,
                                         mav.MAV_CMD_DO_SET_MODE, 0, base, main, sub, 0, 0, 0, 0)
        else:
            self.c.set_mode(mode_id)
        for _ in range(30):
            self.pump(0.2)
            if self.mode.upper() == name.upper():
                return True
        return False

    def set_param(self, name, value, is_int):
        if is_int and self.fw == "px4":
            # PX4 uses byte-wise encoding: the int32 bits travel in the float field
            wire = struct.unpack("<f", struct.pack("<i", int(value)))[0]
            ptype = mav.MAV_PARAM_TYPE_INT32
        else:
            wire = float(value)
            ptype = mav.MAV_PARAM_TYPE_INT32 if is_int else mav.MAV_PARAM_TYPE_REAL32
        self.c.mav.param_set_send(self.c.target_system, self.c.target_component, name.encode(), wire, ptype)
        self.wait(0.3)

    def upload_mission(self, items):
        n = len(items)
        self.c.mav.mission_clear_all_send(self.c.target_system, self.c.target_component)
        self.wait(0.5)
        self.c.mav.mission_count_send(self.c.target_system, self.c.target_component, n, 0)
        sent = set()
        end = time.time() + 30
        while time.time() < end:
            m = self.c.recv_match(type=["MISSION_REQUEST_INT", "MISSION_REQUEST", "MISSION_ACK"], blocking=True, timeout=1)
            if m is None:
                if not sent:
                    self.c.mav.mission_count_send(self.c.target_system, self.c.target_component, n, 0)
                continue
            if m.get_type() == "MISSION_ACK":
                log("mission ack", m.type)
                return m.type == mav.MAV_MISSION_ACCEPTED
            seq = m.seq
            cmd, lat, lon, alt = items[seq]
            log(f"  mission item {seq} requested")
            # RTL has no position: send it in the MISSION frame (PX4 rejects it in a global frame)
            frame = mav.MAV_FRAME_MISSION if cmd == mav.MAV_CMD_NAV_RETURN_TO_LAUNCH else mav.MAV_FRAME_GLOBAL_RELATIVE_ALT_INT
            self.c.mav.mission_item_int_send(self.c.target_system, self.c.target_component, seq,
                                             frame, cmd, 0, 1,
                                             0, 0, 0, float("nan") if self.fw == "px4" else 0,
                                             int(lat * 1e7), int(lon * 1e7), alt, 0)
            sent.add(seq)
        return False


def offset(lat, lon, north, east):
    return lat + north / 111320.0, lon + east / (111320.0 * math.cos(math.radians(lat)))


def angle_diff(a, b):
    return abs((a - b + 180) % 360 - 180)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fw", choices=["ardupilot", "px4"], required=True)
    ap.add_argument("--conn", required=True)
    ap.add_argument("--out", default=".")
    ap.add_argument("--timeout", type=float, default=330)
    args = ap.parse_args()

    result = {"fw": args.fw, "checks": {}, "notes": []}
    t_start = time.time()

    def finish(code):
        result["elapsed_s"] = round(time.time() - t_start, 1)
        path = os.path.join(args.out, f"sitl-{args.fw}.json")
        with open(path, "w") as f:
            json.dump(result, f, indent=2, ensure_ascii=False)
        log("RESULT", json.dumps(result["checks"], ensure_ascii=False))
        sys.exit(code)

    conn = mavutil.mavlink_connection(args.conn, source_system=250, source_component=191, dialect="ardupilotmega" if args.fw == "ardupilot" else "common")
    log("waiting for heartbeat on", args.conn)
    if not conn.wait_heartbeat(timeout=120):
        result["notes"].append("no heartbeat")
        finish(2)
    log("heartbeat from system", conn.target_system, "type", conn.messages["HEARTBEAT"].type)
    v = Vehicle(conn, args.fw)
    conn.mav.request_data_stream_send(conn.target_system, conn.target_component, mav.MAV_DATA_STREAM_ALL, 5, 1)
    v.wait(3)

    if args.fw == "px4":
        # No RC in SITL: allow arming / flying without it
        for name, value, is_int in (("COM_RC_IN_MODE", 4, True), ("NAV_RCL_ACT", 0, True), ("NAV_DLL_ACT", 0, True),
                                    ("COM_RCL_EXCEPT", 7, True), ("MIS_TAKEOFF_ALT", TAKEOFF_ALT, False)):
            v.set_param(name, value, is_int)

    # wait for a position
    end = time.time() + 120
    # wait for a 3D GPS fix and a position
    while (v.lat is None or v.fix < 3) and time.time() < end:
        v.pump(0.5)
    v.wait(5)   # let the estimator settle on that fix
    if v.lat is None:
        result["notes"].append("no position")
        finish(2)
    home_lat, home_lon = v.lat, v.lon
    log("position", home_lat, home_lon)

    # Mission: takeoff, a 300 m square, RTL
    pts = [(0, 300), (300, 300), (300, 0), (0, 0)]
    items = []
    if args.fw == "ardupilot":
        items.append((mav.MAV_CMD_NAV_WAYPOINT, home_lat, home_lon, 0))       # seq 0 = home
    items.append((mav.MAV_CMD_NAV_TAKEOFF, home_lat, home_lon, TAKEOFF_ALT))
    for n, e in pts:
        lat, lon = offset(home_lat, home_lon, n, e)
        items.append((mav.MAV_CMD_NAV_WAYPOINT, lat, lon, TAKEOFF_ALT))
    items.append((mav.MAV_CMD_NAV_RETURN_TO_LAUNCH, 0, 0, 0))
    if not v.upload_mission(items):
        result["notes"].append("mission upload failed")
        finish(2)

    # Arm (retry while the EKF settles) and start the mission
    armed = False
    end = time.time() + 150
    while time.time() < end and not armed:
        if args.fw == "ardupilot":
            v.set_mode("GUIDED")
        r = v.command(mav.MAV_CMD_COMPONENT_ARM_DISARM, 1)
        v.wait(2)
        armed = v.armed
        if not armed:
            log("arm result", r, "- retrying")
            v.wait(3)
    if not armed:
        result["notes"].append("could not arm")
        finish(2)
    log("armed")

    if args.fw == "ardupilot":
        v.command(mav.MAV_CMD_NAV_TAKEOFF, 0, 0, 0, 0, 0, 0, TAKEOFF_ALT)
        end = time.time() + 60
        while v.alt < TAKEOFF_ALT * 0.8 and time.time() < end:
            v.pump(0.5)
        conn.mav.mission_set_current_send(conn.target_system, conn.target_component, 2)
        v.wait(1)
        v.set_mode("AUTO")
    else:
        v.command(mav.MAV_CMD_MISSION_START, 0, 0)
    log("mission started, mode", v.mode)

    # ---- observe ----------------------------------------------------------
    mission_modes = ("AUTO", "MISSION")
    cruise_seen = False
    mission_seen = False
    low_since = None
    speed_ok = False
    pause_alt = None
    pause_t = None
    alt_ok = False
    max_alt_after_pause = -1e9
    hdg_since = None
    hdg_ok = False
    last_log = 0
    end = t_start + args.timeout
    while time.time() < end and not (speed_ok and alt_ok and hdg_ok):
        v.pump(0.25)
        now = time.time()
        in_mission = v.mode.upper() in mission_modes or "MISSION" in v.mode.upper()
        cruising_alt = v.alt > TAKEOFF_ALT * 0.8

        if in_mission and cruising_alt:
            mission_seen = True
            if v.gs > 4.2:
                cruise_seen = True
            if cruise_seen and 1.5 <= v.gs <= 3.5:
                low_since = low_since or now
                if now - low_since >= 8 and not speed_ok:
                    speed_ok = True
                    log(f"CHECK speed_in_mission OK (gs {v.gs:.1f} m/s, mode {v.mode})")
            else:
                low_since = None

        if pause_alt is None and mission_seen and v.armed and cruising_alt and not in_mission and v.mode.upper() not in ("RTL", "LAND", "AUTO.RTL", "AUTO.LAND"):
            pause_alt, pause_t = v.alt, now
            log(f"mission paused by GCS: mode {v.mode} at {v.alt:.1f} m")
        if pause_alt is not None:
            max_alt_after_pause = max(max_alt_after_pause, v.alt)
            if not alt_ok and max_alt_after_pause >= pause_alt + ALT_STEP - 3:
                alt_ok = True
                log(f"CHECK altitude_change OK ({pause_alt:.1f} -> {max_alt_after_pause:.1f} m)")
            if alt_ok and not math.isnan(v.hdg):
                if angle_diff(v.hdg, TEST_HEADING) <= 15:
                    hdg_since = hdg_since or now
                    if now - hdg_since >= 3 and not hdg_ok:
                        hdg_ok = True
                        log(f"CHECK heading_change OK (heading {v.hdg:.0f}°)")
                else:
                    hdg_since = None

        if now - last_log > 5:
            last_log = now
            log(f"mode={v.mode:10s} alt={v.alt:6.1f} gs={v.gs:5.1f} hdg={v.hdg:5.0f} armed={v.armed}")

    result["checks"] = {
        "speed_in_mission": speed_ok,
        "altitude_change": alt_ok,
        "heading_change": hdg_ok,
    }
    result["final"] = {"mode": v.mode, "alt": round(v.alt, 1), "gs": round(v.gs, 1), "hdg": round(v.hdg, 0)}
    if not cruise_seen:
        result["notes"].append("never saw cruise speed above 4.2 m/s in the mission")
    finish(0 if (speed_ok and alt_ok and hdg_ok) else 1)


if __name__ == "__main__":
    main()
