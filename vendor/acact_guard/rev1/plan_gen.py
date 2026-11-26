#!/usr/bin/env python3
"""
plan_gen.py — 시나리오 → QGroundControl 미션 파일(.plan) 생성
════════════════════════════════════════════════════════════════
방법 1) 현장 기준점 직접 입력
   python3 plan_gen.py --center 45.6721000,-118.7880000 --bearing 30
   - center : 시연 구역 중심 위경도
   - bearing: GCS(조종자 위치)에서 시연 구역 중심을 바라보는 방위 [deg, 북=0, 시계방향]
   - 이륙 지점은 config 배치(이륙선 35 m, 간격 15 m)로 계산 → 그 지점에 기체를 놓는다

방법 2) 기체를 이륙 지점에 먼저 놓고 실제 홈 위치로 생성 (SITL 포함, 권장)
   python3 plan_gen.py --from-vehicles              (방위 생략 = 기체 기수 방향 평균으로 자동)
   python3 plan_gen.py --from-vehicles --bearing 30  (직접 지정)
   - mavsdk_server 4개를 자동으로 띄워 각 기체 홈 위치를 읽음 (가드는 꺼 둔 상태에서 실행)
   - 시연 중심 = 4대 홈의 중앙 + bearing 방향 35 m

출력:
   plans/site.json                         (가드가 좌표계·이륙지점 점검에 사용)
   plans/demo/<시나리오>/D1~D4.plan        (본 시연: 시나리오 고도 15 m 공통)
   plans/rehearsal/<시나리오>/D1~D4.plan   (리허설: 기체별 층 고도로 수직 분리)
"""
import argparse
import asyncio
import json
import math
import os

import config as C
import scenarios as SC
from geo import Frame

FENCE_RADIUS = 55.0


def item(seq, cmd, frame, params, alt=None):
    it = {"autoContinue": True, "command": cmd, "doJumpId": seq, "frame": frame,
          "params": params, "type": "SimpleItem"}
    if alt is not None:
        it.update({"AMSLAltAboveTerrain": None, "Altitude": alt, "AltitudeMode": 1})
    return it


def to_plan(items, fr: Frame, home_ll):
    out = []
    seq = 1
    for it in items:
        t = it["t"]
        if t == "speed":
            out.append(item(seq, 178, 2, [1, it["v"], -1, 0, 0, 0, 0]))
        else:
            lat, lon = fr.fr_to_ll(*it["p"]) if t not in ("takeoff", "land") else home_ll
            alt = round(float(it.get("alt", 0.0)), 1)
            if t == "takeoff":
                out.append(item(seq, 22, 3, [0, 0, 0, None, lat, lon, alt], alt))
            elif t == "wp":
                out.append(item(seq, 16, 3, [float(it.get("hold", 0)), 0, 0, None, lat, lon, alt], alt))
            elif t == "sync":
                out.append(item(seq, 17, 3, [0, 0, 0, None, lat, lon, alt], alt))
            elif t == "land":
                out.append(item(seq, 21, 3, [0, 0, 0, None, lat, lon, 0], 0))
        seq += 1
    return {
        "fileType": "Plan",
        "geoFence": {"circles": [{"circle": {"center": list(fr.fr_to_ll(0.0, 0.0)), "radius": FENCE_RADIUS},
                                  "inclusion": True, "version": 1}],
                     "polygons": [], "version": 2},
        "groundStation": "QGroundControl",
        "mission": {"cruiseSpeed": 15, "firmwareType": 12, "globalPlanAltitudeMode": 1,
                    "hoverSpeed": C.SCENARIO_SPEED, "items": out,
                    "plannedHomePosition": [home_ll[0], home_ll[1], 0], "vehicleType": 2, "version": 2},
        "rallyPoints": {"points": [], "version": 2},
        "version": 1,
    }


async def read_homes(host):
    from mavsdk import System
    homes = {}
    for d in C.DRONES:
        s = System(mavsdk_server_address=host, port=d["port"])
        await s.connect()
        async for st in s.core.connection_state():
            if st.is_connected:
                break
        async for h in s.telemetry.home():
            homes[d["id"]] = (h.latitude_deg, h.longitude_deg)
            break
        # 기수 방향 (PX4 나침반, 진북 기준) — 1초 평균
        ys = []
        t_end = asyncio.get_event_loop().time() + 1.0
        async for att in s.telemetry.attitude_euler():
            ys.append(att.yaw_deg)
            if asyncio.get_event_loop().time() > t_end and len(ys) >= 3:
                break
        sx = sum(math.sin(math.radians(y)) for y in ys)
        cx = sum(math.cos(math.radians(y)) for y in ys)
        HEADINGS[d["id"]] = math.degrees(math.atan2(sx, cx)) % 360.0
        print(f"  {d['id']} 홈: {homes[d['id']][0]:.7f}, {homes[d['id']][1]:.7f}   기수 방향 {HEADINGS[d['id']]:.0f}°")
    return homes


HEADINGS = {}


def auto_bearing():
    """기체들의 기수 방향 평균 = 비행 방향 방위. 기체끼리 20° 넘게 다르면 중단."""
    hs = list(HEADINGS.values())
    sx = sum(math.sin(math.radians(h)) for h in hs)
    cx = sum(math.cos(math.radians(h)) for h in hs)
    mean = math.degrees(math.atan2(sx, cx)) % 360.0
    worst = max(abs((h - mean + 180.0) % 360.0 - 180.0) for h in hs)
    if worst > 20.0:
        raise SystemExit(f"\n✖ 기체 기수 방향이 서로 {worst:.0f}° 넘게 다릅니다 {['%s %.0f°' % kv for kv in HEADINGS.items()]}\n"
                         "  두 기체 모두 기수가 비행 방향(시연 구역)을 똑같이 보게 놓고 다시 실행하세요.")
    return mean


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--drones", default=None, help="일부 기체만 (예: D1,D3). 생략 시 4대")
    ap.add_argument("--center", help="lat,lon")
    ap.add_argument("--bearing", default="auto",
                    help="비행 방향 방위 [deg]. 생략(auto)하면 --from-vehicles 일 때 기체 기수 방향으로 자동")
    ap.add_argument("--from-vehicles", action="store_true")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--out", default="plans")
    ap.add_argument("--profile", default=C.PROFILE, choices=list(C.HOME_LAYOUTS),
                    help="oregon(이륙선 1줄) / hwaseong(헬리패드 2×2)")
    a = ap.parse_args()
    C.PROFILE = a.profile
    print(f"프로파일: {a.profile}")

    if not a.from_vehicles:
        a.bearing = 0.0 if a.bearing == "auto" else float(a.bearing)
    if a.from_vehicles:
        print("기체 홈 위치 읽는 중...")
        from servers import Servers
        srv = Servers().start()
        try:
            homes = asyncio.new_event_loop().run_until_complete(asyncio.wait_for(read_homes(a.host), 60))
        finally:
            srv.stop()
        if a.bearing == "auto":
            a.bearing = auto_bearing()
            print(f"  → 비행 방향(방위) 자동: {a.bearing:.0f}° (기체 기수 방향 평균)")
        else:
            a.bearing = float(a.bearing)
        # 각 기체의 실제 홈에서 '권장 배치 위치'만큼 거꾸로 이동한 점 = 시연 중심 후보 → 평균
        #   (4대든 2대든 같은 방식. 기체가 권장 배치대로 놓였다면 모든 후보가 한 점에 모임)
        cands = []
        for k, (hl, hn) in homes.items():
            tmp = Frame(hl, hn, a.bearing)
            hf, hr = SC.home(k)
            cands.append(tmp.fr_to_ll(-hf, -hr))
        clat = sum(c[0] for c in cands) / len(cands)
        clon = sum(c[1] for c in cands) / len(cands)
        fr = Frame(clat, clon, a.bearing)
        # 실제 홈의 좌우 순서 확인
        for k in homes:
            want = SC.home(k)
            got = fr.ll_to_fr(*homes[k])
            dist = ((want[0] - got[0]) ** 2 + (want[1] - got[1]) ** 2) ** 0.5
            if dist > 3.0:
                print(f"  ※ {k} 위치가 권장 배치와 {dist:.0f} m 다름 (권장 전방 {want[0]:+.0f}, 우측 {want[1]:+.0f}) — 기체 번호/위치 확인")
    elif a.center:
        clat, clon = (float(x) for x in a.center.split(","))
        fr = Frame(clat, clon, a.bearing)
        homes = {d: fr.fr_to_ll(*SC.home(d)) for d in SC.IDS}
    else:
        ap.error("--center 또는 --from-vehicles 중 하나가 필요합니다")

    os.makedirs(a.out, exist_ok=True)
    site = {"center_lat": clat, "center_lon": clon, "bearing_deg": a.bearing,
            "homes": {k: list(v) for k, v in homes.items()}}
    with open(os.path.join(a.out, "site.json"), "w", encoding="utf-8") as f:
        json.dump(site, f, indent=2)
    print(f"\n시연 중심: {clat:.7f}, {clon:.7f}  방위 {a.bearing:.0f}°")
    for d in SC.IDS:
        f_, r_ = fr.ll_to_fr(*homes[d])
        print(f"  {d} 이륙지점: {homes[d][0]:.7f}, {homes[d][1]:.7f}  (전방 {f_:+.1f} m, 우측 {r_:+.1f} m)")

    # 시나리오 지점이 이륙 홈을 기준으로 계산되었으므로, 실제 홈이 계획과 다르면 이륙/착륙만 실제 홈 사용
    n = 0
    for mode in ("demo", "rehearsal"):
        for name in SC.SCENARIOS:
            if not SC.available(name):
                continue
            built = SC.build(name, mode)
            d_out = os.path.join(a.out, mode, name)
            os.makedirs(d_out, exist_ok=True)
            for did, items in built.items():
                plan = to_plan(items, fr, homes[did])
                with open(os.path.join(d_out, f"{did}.plan"), "w", encoding="utf-8") as f:
                    json.dump(plan, f, indent=2)
                n += 1
    print(f"\n.plan {n}개 생성 → {a.out}/demo/..., {a.out}/rehearsal/...")


if __name__ == "__main__":
    main()
