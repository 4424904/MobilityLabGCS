#!/usr/bin/env python3
"""
set_params.py — 4대 PX4 안전 파라미터 확인·적용
════════════════════════════════════════════════════════════════
  python3 set_params.py           # 현재값만 확인 (변경 없음)
  python3 set_params.py --apply   # 다른 값만 변경 (확인 후)
PX4 버전에 따라 이름이 없는 파라미터는 '없음'으로 표시된다 → QGC 에서 수동 확인.
가드(guard.py)가 실행 중이면 포트가 겹치므로 가드를 끈 상태에서 실행.
MAV_SYS_ID 는 확인만 한다 (변경은 QGC 에서 하고 재부팅).
"""
import argparse
import asyncio

import config as C

# (이름, 형식, 값 또는 함수(drone_cfg) , 설명)
PARAMS = [
    ("COM_OF_LOSS_T",   "f", 1.0,  "offboard setpoint 끊김 판정 [s]"),
    ("COM_OBL_RC_ACT",  "i", 5,    "offboard 상실 시 동작 = Hold"),
    ("NAV_DLL_ACT",     "i", 2,    "데이터링크(텔레메트리) 상실 시 = Return"),
    ("COM_DL_LOSS_T",   "i", 2,    "데이터링크 상실 판정 [s] — 짧게: 끊긴 기체가 군집 속을 오래 날지 않도록"),
    ("RTL_RETURN_ALT",  "f", lambda d: d["layer"], "RTL 고도 = 기체별 층 고도 (동시 RTL 충돌 방지)"),
    ("RTL_CONE_ANG",    "i", 0,    "★ 0 = 홈 근처에서도 항상 RTL 고도까지 먼저 상승 (기본 45° 면 시연 고도에 머물 수 있음)"),
    ("RTL_DESCEND_ALT", "f", 10.0, "RTL 착륙 전 대기 고도 (층 고도보다 낮게)"),
    ("RTL_TYPE",        "i", 0,    "RTL = 홈으로 복귀"),
    ("GF_ACTION",       "i", 2,    "지오펜스 이탈 시 = Hold"),
    ("GF_MAX_HOR_DIST", "f", 90.0, "홈 기준 최대 수평거리 [m]"),
    ("GF_MAX_VER_DIST", "f", 50.0, "최대 고도 [m]"),
    ("NAV_ACC_RAD",     "f", 2.0,  "웨이포인트 도달 반경 [m] (가드 GOAL_HANDOFF 1.8 과 맞춤)"),
    ("MPC_TKO_SPEED",   "f", 1.0,  "이륙 상승 속도 [m/s] — 천천히 이륙"),
    ("MPC_XY_CRUISE",   "f", 3.0,  "미션 기본 수평속도 [m/s]"),
    ("COM_LOW_BAT_ACT", "i", 3,    "배터리 위험 수준이면 자동 귀환, 비상 수준이면 그 자리 착륙"),
    ("COM_RC_OVERRIDE", "i", 3,    "조종기 스틱 조작 시 미션·offboard 모두 즉시 수동(Position) 전환"),
    ("COM_RC_STICK_OV", "f", 30.0, "수동 전환이 일어나는 스틱 움직임 [%] (기본값)"),
    ("NAV_RCL_ACT",     "i", 2,    "조종기 신호 상실 시 = Return (조종기를 꺼 두면 그 기체는 귀환)"),
    ("COM_RCL_EXCEPT",  "i", 0,    "예외 없음 = 미션·offboard 중에도 조종기 신호 필요 (조종기 켜 두기 강제)"),
]


async def one(d, apply):
    from mavsdk import System
    s = System(mavsdk_server_address="127.0.0.1", port=d["port"])
    print(f"[{d['id']}] 연결 중...")
    await s.connect()
    async for st in s.core.connection_state():
        if st.is_connected:
            break
    print(f"\n[{d['id']}] (gRPC {d['port']})")
    try:
        sid = await s.param.get_param_int("MAV_SYS_ID")
        flag = "OK" if sid == d["sysid"] else f"※ 기대값 {d['sysid']} — QGC 에서 변경 후 재부팅"
        print(f"  MAV_SYS_ID      = {sid:<8} {flag}")
    except Exception:
        print("  MAV_SYS_ID      = 읽기 실패")
    for name, typ, val, desc in PARAMS:
        want = val(d) if callable(val) else val
        try:
            cur = await (s.param.get_param_float(name) if typ == "f" else s.param.get_param_int(name))
        except Exception:
            print(f"  {name:<16}= 없음      ({desc}) ※ PX4 버전 확인")
            continue
        same = abs(cur - want) < 1e-3
        mark = "OK" if same else f"→ {want}"
        print(f"  {name:<16}= {cur:<8} {mark:<10} {desc}")
        if apply and not same:
            try:
                if typ == "f":
                    await s.param.set_param_float(name, float(want))
                else:
                    await s.param.set_param_int(name, int(want))
                print(f"      변경 완료")
            except Exception as e:
                print(f"      변경 실패: {e}")


async def main(apply):
    for d in C.DRONES:
        try:
            await asyncio.wait_for(one(d, apply), timeout=30)
        except asyncio.TimeoutError:
            print(f"\n[{d['id']}] 연결 시간 초과")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--drones", default=None, help="일부 기체만 (예: D1,D3). 생략 시 4대")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--no-spawn", action="store_true", help="mavsdk_server 를 직접 띄운 경우")
    a = ap.parse_args()
    if a.apply and input(f"{len(C.DRONES)}대 파라미터를 변경합니다. 계속? (y/N) ").strip().lower() != "y":
        raise SystemExit
    from servers import Servers
    srv = None
    if not a.no_spawn:
        srv = Servers().start()
    loop = asyncio.new_event_loop()
    try:
        loop.run_until_complete(main(a.apply))
    finally:
        if srv:
            srv.stop()
