# MobilityLab GCS — 구조와 개발자 안내

## 1. 한눈에 보기

```
QGroundControl v5.1.5 (원본, 수정 최소화)
 ├─ patches/0001…0004            원본에 대한 작은 수정 4건 (아래 표)
 └─ custom/                      공식 커스텀 빌드 방식 (QGC_CUSTOM_DIR)
     ├─ src/MLPlugin              QGCCorePlugin 구현: 브랜딩·팔레트·기본 설정·QML 교체·컨텍스트 객체 등록
     ├─ src/MLAcactRuntime        ACACT 가드 실행부 (QGC 링크 위, 20 Hz). 터미널·별도 프로세스 없음
     ├─ src/acact/                ACACT 엔진 (Qt 비의존 C++17) — 원본 Python 을 줄 단위로 옮긴 것
     │    AcactConfig.h           config.py (수정1) — DUO(2대) 설정 포함
     │    AcactCore.*             core.py (수정1) — 예측·판단·회피 속도·제어권 상태기계
     │    AcactScenarios.*        scenarios.py + geo.py — 시나리오 생성, 시연 좌표계
     │    AcactMissionCheck.*     (신규) 사용자 미션 비행 전 검사
     ├─ src/MLFlightAnalysis      가드 기록 분석·리플레이·PDF 보고서
     ├─ src/MLUi                  한/영 전환 (custom/i18n/en.json)
     ├─ src/TandemTelemetry       탠덤 헬기 텔레메트리 (res/tandem.json)
     ├─ qml/MobilityLab/Controls  UI 컴포넌트 (MLTheme·MLState 싱글턴, 콘솔·패널·지도 레이어·분석 화면)
     └─ qml/overrides/            QGC QML 파일 교체 (FlyView, 툴바, 확인 버튼 등)
vendor/acact_guard/              원본 보존: oregon_demo(이전판) · rev1(수정1, 기준) · archives(zip 원본) · ORIGIN.md
tools/                           CI·검증 스크립트 (아래 6절)
```

## 2. ACACT 실행 구조

```
 PX4 기체 ──MAVLink──▶ QGC LinkManager / Vehicle ──mavlinkMessageReceived──▶ MLAcactRuntime
                                                                               │  HEARTBEAT, GLOBAL_POSITION_INT, ATTITUDE,
                                                                               │  EXTENDED_SYS_STATE, SYS_STATUS, GPS_RAW_INT,
                                                                               │  HOME_POSITION, MISSION_CURRENT
                                                                               ▼
                                             _tick() 20 Hz (GUI 스레드 QTimer)
                                               ├─ DroneIn 구성 (시연 좌표계 F/R, 고도, 속도, 모드, 신선도)
                                               ├─ GuardCore::step()  ← 원본 core.py 와 동일한 판단
                                               └─ Command 처리
                                                    Takeover → MAV_CMD_DO_SET_MODE (OFFBOARD) + 속도 스트림
                                                    Vel      → SET_POSITION_TARGET_LOCAL_NED (속도+yaw)
                                                    Release  → 미션 모드 복귀
                                                    Advance  → goto_next_item (MISSION_SET_CURRENT, 확인·재시도)
                                                    Event    → 이벤트 로그 / 화면
```

* **안전 설계**
  * 속도 설정점은 GUI 스레드 타이머에서만 나간다. GCS 가 멈추거나 죽으면 스트림이 끊기고, PX4 가 `COM_OF_LOSS_T` 뒤 Offboard 상실 페일세이프로 들어간다. CI `gcskill` 시험에서 확인한다.
  * 정상 종료 시(`aboutToQuit`)에는 가드가 비행 중이던 기체를 HOLD 로 바꾼다.
  * 조종기 수동 모드인 기체는 넘겨받지 않는다.
  * 운용자가 QGC 확인 버튼으로 명령을 보내면 `operatorCommand()` 를 거쳐 그 기체를 즉시 운용자에게 넘긴다. 이후 미션이 재개될 때까지 다시 잡지 않는다.
  * 가드가 명령하지 않은 Offboard(고아 Offboard)는 감지해서 HOLD 로 바꾼다.
* **지원 범위**: 회피 제어는 PX4 멀티콥터만 한다. 다른 기체(ArduPilot, 헬기, 고정익)는 장애물로만 다룬다.
* **QGC 와 제어 충돌 방지**
  * 가드가 비행 중인 기체에 QGC 명령이 들어오면 위 운용자 우선 규칙을 따른다.
  * 회피 중에는 미션 교체(.plan 업로드)를 거부한다.
  * 미션 업로드 중(`_missionWriting`)에는 미션 변경 감지를 운용자 편집으로 보지 않는다.

## 3. 원본 대비 검증

| 대상 | 방법 | 위치 |
|---|---|---|
| core.py / config.py | 같은 시뮬레이터(rev1 `sim_check.run`)를 세 가지로 돌림: Python·C++ 동시 실행(매 스텝 명령·쌍 판정·제어권 비교), Python 단독, C++ 단독(폐루프, 결과 일치). 정상 조건·스트레스·GPS 오차·통신 두절 주입 포함 120회 | `tools/acact_verify/acact_compare.py` |
| scenarios.py / geo.py | 모든 시나리오 × 모드 × 프로파일 × 기체 조합 270건, 좌표 변환 2,000건 | `tools/acact_verify/acact_compare_missions.py` |
| C API | 위 비교를 위한 ctypes 인터페이스 | `tools/acact_verify/acact_capi.cc` |

CI 가 빌드할 때마다 돌린다. 원본은 `vendor/acact_guard/rev1` 이고, `SHA256SUMS` 로 변경 여부를 확인할 수 있다.

## 4. 사용자 미션 검사 (AcactMissionCheck)

| 구분 | 항목 |
|---|---|
| 기체별 | 미션 없음, 위치 항목 없음, 이륙점 ↔ 기체 위치, 최고/최저 고도, 홈에서 거리, 지오펜스(허용 원·다각형 / 금지 구역, 경로 5 m 간격), 끝 동작(LAND/RTL), 배터리(완충 비행 시간 기준), 해발·지형 고도 프레임 |
| 기체쌍 | 경로 최소 수평거리(같은 층), 동시 출발 시간 예측 최소거리, 이착륙 지점 간격, 같은 미션 중복 |

* **등급**
  * 오류: 일괄 시작을 막는다.
  * 주의: ACACT 가 해결할 근접이다.
  * 정보
* **재검사**: 미션이나 지오펜스가 바뀌면 400 ms 뒤에 자동으로 다시 검사한다.
* **회귀 시험**: 30건 (`tools/acact_verify/mission_check_test.cc`).

## 5. 실비행 / 시뮬레이션 모드

* 기체 판별은 파라미터로 한다.
  * PX4 SITL: `SIM_BAT_DRAIN` 이 있다.
  * HITL: `SYS_HITL > 0`.
  * ArduPilot SITL: `SIM_SPEEDUP` 또는 `SIM_GPS_USED` 가 있다.
* 시뮬레이션 모드에 실기체가 섞이거나, 실비행 모드에 SITL 기체가 섞이면 가드를 시작하지 않는다.
* 시뮬레이션 모드에서 비행을 끝까지 마치면 그 계획의 서명을 SITL 기록으로 남긴다. 조건은 모든 기체가 착륙·시동 꺼짐이고, 최소 이격이 D_EMERG 이상이며, 내부 오류가 없는 것이다.
  * 시나리오 서명 = 이름 / 모드 / 배치 / 기체 목록.
  * 사용자 미션 서명 = 항목 해시.
* 실비행 모드에서는 SITL 기록이 있는 계획만 일괄 시작한다. 예외는 운용자가 "검증 없이 진행"을 두 번 누른 경우뿐이고, 이 경우 로그에 남는다.

## 6. 기록 · 분석

* **가드 실행마다 남기는 파일** (문서 폴더 `MobilityLab/ACACT`, 포터블은 `data/ACACT`)
  * `guard_<시각>.csv`: 20 Hz
  * `_events.csv`
  * `_summary.txt`
  * `_meta.json`: 구역, 기체, 기준값, 계획, 운용 모드
* **MLFlightAnalysis** 가 이 파일들을 읽는다.
  * 세션 목록
  * 리플레이 (`stateAt`)
  * 쌍별 최소 이격·D_SAFE/D_EMERG 미만 시간
  * 기체별 개입 횟수·시간·링크 공백
  * 개입 이력
  * 자동 판정
  * PDF 보고서 (`QPdfWriter`, A4)
* **회귀 시험**: `tools/acact_verify/analysis_test.cc` (합성 기록).

## 7. 원본 QGC 수정 (patches/)

| 파일 | 내용 |
|---|---|
| 0001-vworld-layer-name | VWorld 지도 레이어 이름 오류 수정 |
| 0002-no-modal-on-extra-vehicle | 기체가 추가될 때 뜨는 모달 창 제거 (다기체 운용) |
| 0003-critical-message-handler | 치명 메시지를 커스텀 배너로 넘기는 훅 |
| 0004-portable-settings | 실행 파일 상위 폴더에 `portable.txt` 가 있으면 설정을 그 아래 `data/` 에 저장 |
| tools/patch_installer.py | Windows 설치 스크립트: 바탕화면 바로가기, 설치 후 실행, 한국어 화면 |
| tools/apply_ko.py | QGC 한국어 번역의 미번역 항목 보충 |

## 8. 확장 (헬기·고정익)

* `MLAcactRuntime::VS::supported` 가 "가드가 제어할 수 있는 기체"를 정한다. 지금은 PX4 멀티콥터만 해당한다.
* 헬기·고정익으로 넓히려면 다음을 해야 한다.
  1. 기체 종류별 회피 명령 계층을 만든다. 고정익은 속도 벡터 대신 선회·고도 명령을 쓴다.
  2. `GuardCore` 의 속도 제한·반경을 기체 프로파일에서 받는다.
  3. SITL(ArduPlane / PX4 고정익)로 동등성과 회피를 검증한다.
* 엔진은 Qt 에 의존하지 않으므로 프로파일만 바꿔 같은 시험 도구로 검증할 수 있다.

## 9. CI 와 시험 (`.github/workflows/build.yml`)

| 작업 | 내용 |
|---|---|
| linux (Ubuntu 22.04) | 원본 동등성 + 미션검사 + 번역 누락 검사 → 빌드 → 분석/PDF 회귀 → AppImage → AppImage 부팅 시험 → 모의 기체 화면 점검 |
| px4 | PX4 v1.16.2 SITL 바이너리 (캐시) |
| sitl (Ubuntu 24.04, AppImage) | `targets`(목표 조정, ArduPilot+PX4), `s7duo`, `preflight`, `user`, `gcskill`, `linkloss`, `operator` |
| report | 결과를 `ci-screens` 브랜치에 공개 (스크린샷, 로그, sitl-*.json, 요약표) |
| windows | 빌드 → NSIS 설치 파일 → 무인 설치·부팅·GUI 실행·포터블 zip·포터블 실행·제거 시험 → `ci-windows` 브랜치 |

SITL 시나리오의 상세 판정 기준은 `tools/acact_sitl.py` 머리말에 있다. 운용자 동작은 `MLAcactTestDriver.qml` 이 흉내 낸다.
