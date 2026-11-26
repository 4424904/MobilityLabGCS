#!/usr/bin/env python3
"""
fake_guard.py — stands in for ACACT Guard (acact_guard/guard.py + gcs_link.py)
in the CI screen check. Sends the guard's GCS status JSON for two drones that
follow fake_vehicle.py --orbit duo, and logs the commands the GCS sends back.

The prediction here is deliberately simple (straight-line CPA over 6 s); the
real guard's logic lives in acact_guard/core.py.
"""
import argparse
import json
import math
import socket
import time

from fake_vehicle import duo_state, HOME_LAT

D_SAFE, T_LOOK = 12.0, 6.0


def fr(lat, lon):
    n = (lat - HOME_LAT) * 111320.0
    e = (lon - 126.83) * 111320.0 * math.cos(math.radians(HOME_LAT))
    return n, e


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--delay2", type=float, default=25.0, help="vehicle 2 started this many seconds later")
    ap.add_argument("--duration", type=float, default=150)
    ap.add_argument("--target", default="127.0.0.1:47001")
    a = ap.parse_args()
    host, port = a.target.rsplit(":", 1)
    tx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    rx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    rx.bind(("127.0.0.1", 47002))
    rx.setblocking(False)
    t0 = time.time()
    events, seq, own_since, min_sep, auto = [], 0, None, None, True

    def ev(t, who, text):
        nonlocal seq, events
        seq += 1
        events = (events + [{"n": seq, "t": round(t, 1), "who": who, "text": text}])[-20:]
        print(f"[{t:6.1f}] {who} {text}", flush=True)

    ev(0, "SYS", "가드 시작 (CI 대역)")
    while time.time() - t0 < a.duration:
        t = time.time() - t0
        drones = []
        st = {}
        for sid, tt in ((1, t), (2, t - a.delay2)):
            if tt < 0:
                continue
            lat, lon, alt, vn, ve = duo_state(sid, tt)
            st[sid] = (lat, lon, alt, vn, ve)
        pairs = []
        level = 0
        if 1 in st and 2 in st:
            n1, e1 = fr(st[1][0], st[1][1]); n2, e2 = fr(st[2][0], st[2][1])
            dn, de = n2 - n1, e2 - e1
            dvn, dve = st[2][3] - st[1][3], st[2][4] - st[1][4]
            d = math.hypot(dn, de)
            vv = dvn * dvn + dve * dve
            tc = max(0.0, min(T_LOOK, -(dn * dvn + de * dve) / vv)) if vv > 1e-6 else 0.0
            cpa = math.hypot(dn + dvn * tc, de + dve * tc)
            level = 2 if d < 5.5 else (1 if cpa < D_SAFE else 0)
            min_sep = d if min_sep is None else min(min_sep, d)
            pairs.append({"a": "D1", "b": "D2", "d": round(d, 2), "dz": round(st[2][2] - st[1][2], 2), "level": level,
                          "cpa": round(cpa, 2), "tcpa": round(tc, 1), "min": round(min_sep, 2)})
            if level and own_since is None:
                own_since = t
                ev(t, "D2", f"회피 개입 (D1 예측 최근접 {cpa:.1f} m, {tc:.0f}초 후)")
            elif not level and own_since is not None and t - own_since > 3:
                own_since = None
                ev(t, "D2", "위험 해소 → 미션 복귀")
        for sid, (lat, lon, alt, vn, ve) in st.items():
            drones.append({"id": f"D{sid}", "sysid": sid, "connected": True, "lat": lat, "lon": lon, "alt": round(alt, 2),
                           "vn": round(vn, 2), "ve": round(ve, 2), "mode": "OFFBOARD" if (sid == 2 and own_since) else "MISSION",
                           "own": bool(sid == 2 and own_since), "yield": False, "lock": False, "fresh": True,
                           "batt": 78.0 - t / 20, "seq": 4, "total": 9, "takeovers": 1})
        msg = {"proto": 1, "src": "acact_guard", "t": round(t, 2), "auto": auto, "loaded": ["S7_duo", "demo"],
               "cfg": {"d_safe": D_SAFE, "d_emerg": 5.5, "v_sep": 4.0, "t_look": T_LOOK, "rs": 14.0, "duo": True, "profile": "hwaseong"},
               "site": {"lat": HOME_LAT, "lon": 126.83 + 40.0 / (111320.0 * math.cos(math.radians(HOME_LAT))), "bearing": 90.0, "radius": 25.0},
               "drones": drones, "pairs": pairs, "events": events}
        tx.sendto(json.dumps(msg).encode(), (host, int(port)))
        try:
            while True:
                data, addr = rx.recvfrom(4096)
                c = json.loads(data.decode()).get("cmd", "")
                ev(t, "GCS", f"GCS 명령: {c}")
                if c in ("auto on", "auto off"):
                    auto = c == "auto on"
        except (BlockingIOError, OSError, ValueError):
            pass
        time.sleep(0.2)


if __name__ == "__main__":
    main()
