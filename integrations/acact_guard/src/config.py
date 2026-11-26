"""
config.py — ACACT Guard 공통 설정
════════════════════════════════════════════════════════════════
현장에서 바꿀 값은 대부분 이 파일에 있다.
좌표계: 시연 프레임 (F, R)
  F = forward  : GCS(조종자)에서 시연 구역 쪽 방향 (+)
  R = right    : GCS에서 바라봤을 때 오른쪽 (+)
  시연 구역 중심 C = (0, 0)
"""

# ── 기체 ───────────────────────────────────────────────────────
# id      : 화면/로그 표시 이름 (D1 = 가장 높은 우선순위)
# port    : mavsdk_server gRPC 포트
# udp     : mavsdk_server 가 듣는 MAVLink UDP 포트 (mavlink-router / SITL)
# layer   : 이동(트랜짓)·리허설 고도 및 RTL 고도 [m, 이륙지점 기준]
DRONES = [
    {"id": "D1", "sysid": 1, "port": 50051, "udp": 14541, "layer": 20.0},
    {"id": "D2", "sysid": 2, "port": 50052, "udp": 14542, "layer": 26.0},
    {"id": "D3", "sysid": 3, "port": 50053, "udp": 14543, "layer": 32.0},
    {"id": "D4", "sysid": 4, "port": 50054, "udp": 14544, "layer": 38.0},
]
ALL_DRONES = list(DRONES)

# ── 일부 기체만 비행 (예: 2대) ──────────────────────────────────
#   모든 프로그램에 --drones D1,D3 를 붙이거나 환경변수 ACACT_DRONES=D1,D3
#   권장 2대 조합: D1,D3 (교차·정면 교차가 그대로 정면으로 마주침)
def _active_ids():
    import os as _o, sys as _s
    v = _o.environ.get("ACACT_DRONES", "")
    if "--drones" in _s.argv:
        i = _s.argv.index("--drones")
        if i + 1 < len(_s.argv):
            v = _s.argv[i + 1]
    ids = [x.strip().upper() for x in v.split(",") if x.strip()]
    return ids or [d["id"] for d in ALL_DRONES]
_ids = _active_ids()
_bad = [x for x in _ids if x not in [d["id"] for d in ALL_DRONES]]
if _bad:
    raise SystemExit(f"--drones 에 알 수 없는 기체: {_bad} (D1~D4 중에서)")
DRONES = [d for d in ALL_DRONES if d["id"] in _ids]

DEMO_ALT = 8.0           # 본 시연 공통 고도 [m] — 참관자가 잘 보이도록 낮게
TAKEOFF_ALT = 8.0        # 이륙 고도 [m] (천천히 이륙 후 이 고도에서 대기)
TAKEOFF_SPEED = 1.0      # 이륙 상승 속도 [m/s] — PX4 MPC_TKO_SPEED 와 같게 (set_params.py)
STEP_FWD = 2.0           # 이륙 후 앞으로 나가는 거리 [m] (출발 신호용 작은 기동)
PAD_ZONE = 4.0           # 이륙지점에서 이 거리 안이면 '이륙 구역' — 서로 충돌 판정 안 함 (자리 간격 10 m 이상)

# ── 현장 배치 (시연 프레임, m) ─────────────────────────────────
HOME_LINE_F = -35.0      # 이륙선: 중심에서 GCS 쪽으로 35 m
HOME_SPACING = 15.0      # 이륙 지점 간격 (D1 왼쪽 → D4 오른쪽)

# 현장 프로파일: 이륙 지점 배치만 다르고 시나리오 비행 구역은 동일
#   oregon   : 이륙선 1줄, 15 m 간격 (기본)
#   hwaseong : 화성 드론시험센터 헬리패드2 (21×21 m) 위 2×2 배치, 10 m 간격
#              패드 중심이 시연 중심에서 42 m 뒤. 패드 가장자리→펜스 3 m 이므로 펜스는 전방 -28.5 m,
#              가장 가까운 비행점(-26 m)이 펜스 너머 2.5 m 이상 → 모든 기동이 펜스 너머에서 이뤄짐
import os as _os
PROFILE = _os.environ.get("ACACT_PROFILE", "oregon")
HOME_LAYOUTS = {
    "oregon": None,   # HOME_LINE_F / HOME_SPACING 으로 계산
    # 오리건 2대: 이륙선 가운데에 15 m 간격 (D1 왼쪽, D2 오른쪽)
    "oregon2": {"D1": (-35.0, -7.5), "D2": (-35.0, 7.5), "D3": (-35.0, 22.5), "D4": (-35.0, -22.5)},
    "hwaseong": {"D1": (-37.0, -5.0), "D2": (-37.0, 5.0), "D3": (-47.0, -5.0), "D4": (-47.0, 5.0)},
}
HOME_CENTER_F = {"oregon": HOME_LINE_F, "oregon2": HOME_LINE_F, "hwaseong": -42.0}   # 이륙 지점 중앙의 전방 좌표
SCENARIO_RADIUS = 25.0   # 교차 시나리오 반경

# ── 속도 ──────────────────────────────────────────────────────
TRANSIT_SPEED = 5.0      # 층 고도 이동 속도 [m/s] (수직 분리된 구간)
LOW_TRANSIT_SPEED = 3.0  # 시연 고도(8 m)에서 시작점으로 바로 이동할 때 속도 [m/s]
SCENARIO_SPEED = 3.0     # 시나리오 구간 [m/s] (2.0 → 3.0 상향, sim_check 로 검증)

# ── 충돌 가드 ─────────────────────────────────────────────────
LOOP_HZ = 20
TELEM_HZ = 10
PRESTREAM_HZ = 5         # 대기 중 offboard setpoint 선행 송신 (개입 지연 단축)
STALE_T = 1.5            # 텔레메트리 이 시간 이상 끊기면 STALE [s]
STALE_PREDICT_MAX = 8.0  # STALE 기체 위치 외삽 최대 시간 [s]
DL_LOSS_T = 2.0          # PX4 COM_DL_LOSS_T 와 동일하게 (set_params.py) [s]
AUTO_SYNC = True         # 자동 진행: 4대가 대기점에 도착·정지하면 AUTO_SYNC_DELAY 후 자동으로 다음 기동
BATT_WARN = 35.0         # 비행 중 이 % 미만이면 경고 [%]
AUTO_LAND = True         # 착륙도 자동 (False 면 착륙 직전만 수동 g)
AUTO_SYNC_DELAY = 5.0    # 자동 진행 대기 시간 [s] — 도착 후 자세 안정 2~3 s + 여유
DEGRADED_MARGIN = 2.0    # 통신 두절 기체가 있을 때 추가 여유 거리 [m]
STALE_DROP_T = 30.0      # 통신 두절 후 이 시간 지나면 RTL 귀환 중으로 보고 판단에서 제외 [s]

D_SAFE = 10.0            # 예측 최근접 거리가 이보다 작으면 개입 [m] (속도 3 m/s 기준)
D_EMERG = 5.5            # 현재 거리가 이보다 작으면 긴급 (정지+고도 분리) [m]
T_LOOK = 6.0             # 최근접점 예측 시간창 [s]
V_SEP = 4.0              # 고도차가 이 이상이면 서로 무시 [m]
RELEASE_MARGIN = 2.0     # 해제 판정은 D_SAFE + 이 값 [m]
RELEASE_HOLD = 2.0       # 위험 해소 후 이 시간 유지되면 미션 복귀 [s]
MIN_OWN_TIME = 3.0       # 한 번 개입하면 최소 유지 시간 [s]
MIN_TAKEOVER_ALT = 5.0   # 이 고도 미만에서는 개입하지 않음 [m]
GOAL_HANDOFF = 1.8       # 회피 중 목표 WP 이 거리 안이면 미션에 넘김 (NAV_ACC_RAD 2 m 보다 작게) [m]

MAX_H_SPEED = 3.0        # 회피 중 수평 최대 속도 [m/s]
MAX_CLIMB = 1.0          # 긴급 고도 분리 상승 속도 [m/s]
EMERG_CLIMB_MAX = 6.0    # 긴급 상승 최대량 (개입 시점 고도 기준) [m]
ALT_HOLD_KP = 0.8        # 회피 중 고도 유지 P 게인

# ── ACACT 파라미터 (Min & Nam, IEEE Access 2023 기반) ─────────
ACACT = dict(
    kpa=0.6,       # 인력 게인
    kpp=1.5,       # 위치 반발 게인
    kpv=0.3,       # 상대속도 반발 게인
    rs=12.0,       # 반발 반경 [m]
    ts=3.0,        # 안전 시간 [s]
    k_rh=1.2,      # 우측 통행 보정 게인 (대칭 정면 교착 방지)
    k_cpa=2.0,     # 예측 최근접점 기반 사전 우측 회피 게인 [m/s]
    goal_tol=1.0,
)

# ── 시연 화면 / 로그 ──────────────────────────────────────────
MAP_UDP = ("127.0.0.1", 47000)

# ── MobilityLab GCS 연결 (gcs_link.py) ─────────────────────────
#   GCS 가 다른 PC 에 있으면 환경변수 ACACT_GCS=<GCS IP>:47001 (쉼표로 여러 곳)
GCS_STATUS_TARGETS = [("127.0.0.1", 47001)]   # 가드 상태 → GCS (5 Hz)
GCS_CMD_PORT = 47002                          # GCS → 가드 명령 수신 포트
GCS_CMD_ALLOW = ["127.0.0.1"]                 # 명령을 받을 GCS 주소 (ACACT_GCS 주소는 자동 포함)
GCS_ALLOW_LOAD_START = False                  # load/start 는 가드 터미널에서만 (현장 절차 유지)
LOG_DIR = "logs"
SITE_FILE = "plans/site.json"

# ── 2대 비행 전용 설정 (오리건 2대 시연) ─────────────────────────
#   2대는 서로 피할 공간이 넓어 회피를 더 빠르고 일찍 하게 함 → 회피 순간에도 감속이 적어 날렵하게 보임
#   (시뮬 검증: S7_duo 최소 이격 7.8 m, GPS ±2 m 6.6 m, 통신 두절 주입 7.9 m 이상)
DUO = len(DRONES) == 2
if DUO:
    MAX_H_SPEED = 4.5        # 회피 중 최대 속도 (4대: 3.0)
    D_SAFE = 12.0            # 개입 판단 거리 (4대: 10.0)
    ACACT["rs"] = 14.0       # 반발 반경 (4대: 12.0)
    ACACT["k_cpa"] = 3.0     # 미리 오른쪽으로 비키는 세기 (4대: 2.0)
