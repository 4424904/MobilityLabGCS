#!/usr/bin/env python3
"""
MobilityLab GCS - simulated tandem helicopter (MAVLink over UDP).

Sends the telemetry the GCS tandem panel understands so the UI can be checked
without an aircraft or SITL:
  HEARTBEAT, ATTITUDE, GLOBAL_POSITION_INT, VFR_HUD, GPS_RAW_INT, SYS_STATUS,
  EXTENDED_SYS_STATE, HOME_POSITION, BATTERY_STATUS (main/aux),
  EFI_STATUS (engine), RPM (front/rear rotor), NAMED_VALUE_FLOAT (gearbox,
  oil, coolant, fuel).

Usage:
  pip install pymavlink
  python fake_vehicle.py                       # sends to 127.0.0.1:14550
  python fake_vehicle.py --scenario faults     # adds caution/warning conditions after 20 s
  python fake_vehicle.py --duration 120

This is a display test tool only. It does not fly and ignores commands except
for acknowledging them.
"""

import argparse
import math
import os
import time

os.environ.setdefault("MAVLINK20", "1")
from pymavlink import mavutil  # noqa: E402

mavutil.set_dialect("ardupilotmega")
mav = mavutil.mavlink

HOME_LAT = 37.2100
HOME_LON = 126.8300
HOME_ALT = 20.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", default="udpout:127.0.0.1:14550")
    ap.add_argument("--scenario", choices=["normal", "faults"], default="normal")
    ap.add_argument("--duration", type=float, default=0, help="seconds, 0 = run forever")
    ap.add_argument("--rate", type=float, default=10.0, help="telemetry Hz")
    args = ap.parse_args()

    conn = mavutil.mavlink_connection(args.target, source_system=1, source_component=1)
    m = conn.mav

    t0 = time.time()
    last_hb = 0.0
    sent_home = False
    radius = 350.0
    speed = 14.0

    while True:
        now = time.time()
        t = now - t0
        if args.duration and t > args.duration:
            break
        boot_ms = int(t * 1000)

        # ---- incoming: acknowledge what QGC asks for -----------------------
        while True:
            msg = conn.recv_match(blocking=False)
            if msg is None:
                break
            mt = msg.get_type()
            if mt == "PARAM_REQUEST_LIST":
                m.param_value_send(b"SYSID_THISMAV", 1.0, mav.MAV_PARAM_TYPE_REAL32, 1, 0)
            elif mt == "MISSION_REQUEST_LIST":
                m.mission_count_send(msg.get_srcSystem(), msg.get_srcComponent(), 0,
                                     getattr(msg, "mission_type", 0))
            elif mt == "COMMAND_LONG":
                if msg.command == mav.MAV_CMD_REQUEST_MESSAGE and int(msg.param1) == mav.MAVLINK_MSG_ID_AUTOPILOT_VERSION:
                    send_autopilot_version(m)
                m.command_ack_send(msg.command, mav.MAV_RESULT_ACCEPTED)

        # ---- 1 Hz ----------------------------------------------------------
        if now - last_hb >= 1.0:
            last_hb = now
            m.heartbeat_send(mav.MAV_TYPE_HELICOPTER, mav.MAV_AUTOPILOT_GENERIC,
                             mav.MAV_MODE_FLAG_SAFETY_ARMED | mav.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED
                             | mav.MAV_MODE_FLAG_AUTO_ENABLED,
                             0, mav.MAV_STATE_ACTIVE)
            m.extended_sys_state_send(mav.MAV_VTOL_STATE_UNDEFINED, mav.MAV_LANDED_STATE_IN_AIR)
            m.sys_status_send(0, 0, 0, 500, 28100, 1200, 72, 0, 0, 0, 0, 0, 0)
            if not sent_home:
                m.home_position_send(int(HOME_LAT * 1e7), int(HOME_LON * 1e7), int(HOME_ALT * 1000),
                                     0, 0, 0, [1, 0, 0, 0], 0, 0, 0)
                sent_home = True

        # ---- flight: steady circle around a point east of home -------------
        ang = speed * t / radius
        north = radius * math.sin(ang)
        east = 600 + radius * math.cos(ang)
        lat = HOME_LAT + north / 111320.0
        lon = HOME_LON + east / (111320.0 * math.cos(math.radians(HOME_LAT)))
        alt = 80 + 3 * math.sin(t / 9)
        hdg = (math.degrees(ang) + 180) % 360  # tangent of the circle, counter-clockwise
        vn = speed * math.cos(ang)
        ve = -speed * math.sin(ang)
        roll = math.radians(-12 + 1.5 * math.sin(t * 1.7))
        pitch = math.radians(-5 + 0.8 * math.sin(t * 1.3))

        m.attitude_send(boot_ms, roll, pitch, math.radians(hdg if hdg <= 180 else hdg - 360), 0, 0, 0)
        m.global_position_int_send(boot_ms, int(lat * 1e7), int(lon * 1e7), int((HOME_ALT + alt) * 1000),
                                   int(alt * 1000), int(vn * 100), int(ve * 100), 0, int(hdg * 100))
        m.vfr_hud_send(speed, speed, int(hdg), 62, HOME_ALT + alt, 0.2 * math.cos(t / 9))
        m.gps_raw_int_send(boot_ms * 1000, 6, int(lat * 1e7), int(lon * 1e7), int((HOME_ALT + alt) * 1000),
                           60, 90, int(speed * 100), int(hdg * 100), 18)

        # ---- tandem systems -------------------------------------------------
        faults = args.scenario == "faults" and t > 20
        engine_rpm = 5450 + 25 * math.sin(t / 3)
        front = 520 + 2 * math.sin(t / 2)
        rear = front * (1 - (0.032 if faults else 0.004))
        coolant = 113 if faults else 88 + 2 * math.sin(t / 20)
        fuel_pct = max(5.0, 54 - t * 0.02)

        m.efi_status_send(1, 0, engine_rpm, 812.0, 405.0, 64.0, 62.0, 0, 101.3, 95.0, 34.0,
                          coolant + 6, 22.0, 3.1, 712.0, 62.0, 0, 13.8, 300.0)
        m.rpm_send(front, rear)
        for name, value in (("GB_F_T", 68.0), ("GB_R_T", 71.0), ("OIL_T", 96.0), ("OIL_P", 4.2),
                            ("COOL_T", coolant), ("FUEL_PCT", fuel_pct), ("FUEL_L", fuel_pct * 0.75)):
            m.named_value_float_send(boot_ms, name.encode(), value)

        cells = [28100] + [65535] * 9
        m.battery_status_send(0, mav.MAV_BATTERY_FUNCTION_ALL, mav.MAV_BATTERY_TYPE_LIPO, 2500,
                              cells, 1200, -1, -1, 72)
        aux = [13200] + [65535] * 9
        m.battery_status_send(1, mav.MAV_BATTERY_FUNCTION_AVIONICS, mav.MAV_BATTERY_TYPE_LIPO, 2500,
                              aux, 150, -1, -1, 90)

        time.sleep(1.0 / args.rate)


def send_autopilot_version(m):
    caps = (mav.MAV_PROTOCOL_CAPABILITY_MISSION_INT | mav.MAV_PROTOCOL_CAPABILITY_COMMAND_INT
            | mav.MAV_PROTOCOL_CAPABILITY_PARAM_FLOAT | mav.MAV_PROTOCOL_CAPABILITY_MAVLINK2)
    m.autopilot_version_send(caps, 0, 0, 0, 0, [0] * 8, [0] * 8, [0] * 8, 0, 0, 0)


if __name__ == "__main__":
    main()
