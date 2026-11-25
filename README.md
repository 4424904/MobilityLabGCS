# MobilityLab GCS

모빌리티랩 지상통제 프로그램(GCS). 멀티콥터(X500 등)·헬리콥터(탠덤 포함)·고정익·VTOL 등 MAVLink 기체 공용이며, 여러 대 동시 연결도 지원한다. QGroundControl(QGC) v5.1.5를 기반으로, QGC 원본은 건드리지 않고 공식 커스텀 플러그인(`custom/`) 방식으로 만든다.

## 받아서 쓰기 (Windows)

1. 이 저장소 GitHub 페이지 → **Actions** 탭 → 가장 최근의 초록색 체크 표시가 있는 `Build MobilityLab GCS` 실행을 연다.
2. 아래 **Artifacts**에서 `MobilityLabGCS-Windows-installer`를 내려받아 압축을 푼다.
3. `MobilityLabGCS-installer-*.exe`를 실행해 설치한다.

## 구성

| 경로 | 내용 |
|---|---|
| `custom/` | QGC 커스텀 플러그인. 빌드 시 QGC 소스의 `custom/` 위치로 복사된다 |
| `custom/src/MLPlugin.*` | 브랜딩·팔레트·한국어/VWorld 기본값, QML 교체 |
| `custom/src/TandemTelemetry.*` | 엔진·로터·연료·전원 텔레메트리 수신, 경고/주의 판정 |
| `custom/res/tandem.json` | 메시지 매핑과 경고 임계값 (**현재 임시값**) |
| `custom/qml/MobilityLab/Controls/` | 콘솔 패널 UI (비행계기, 추진·전원·항법·경고 패널, 미션 목록, 명령 바) |
| `custom/qml/overrides/` | QGC 비행 화면 교체 (단일 모니터 콘솔 배치) |
| `patches/` | QGC 원본에 대한 최소 수정 (VWorld 지도 레이어 이름 버그) |
| `tools/fake_vehicle.py` | 기체 없이 화면을 확인하는 가상 기체 (탠덤 헬기/쿼드, 미션 포함, pymavlink) |
| `.github/workflows/build.yml` | Linux 빌드·화면 캡처, Windows 설치파일 빌드 |

## 텔레메트리 매핑

| 화면 항목 | MAVLink |
|---|---|
| 엔진 RPM·실린더헤드/배기 온도·스로틀·연료 유량/압력 | `EFI_STATUS` |
| 전방/후방 로터 RPM | `RPM`(rpm1/rpm2) 또는 `RAW_RPM`(index 0/1) |
| 기어박스·오일·냉각수 온도, 연료 잔량 | `NAMED_VALUE_FLOAT` (`GB_F_T`, `GB_R_T`, `OIL_T`, `OIL_P`, `COOL_T`, `FUEL_PCT`, `FUEL_L`) |
| 주/보조 배터리 | `BATTERY_STATUS` id 0 / 1 |
| 발전기 | `GENERATOR_STATUS` |

ICD가 확정되면 `tandem.json`만 바꾸면 된다. 설치된 PC에서는 `%LOCALAPPDATA%\MobilityLab\MobilityLabGCS\tandem.json`에 복사본을 두면 다시 빌드하지 않고 덮어쓸 수 있다.

## 기체 없이 화면 확인

```
pip install pymavlink
python tools/fake_vehicle.py                  # 정상 비행
python tools/fake_vehicle.py --scenario faults  # 20초 후 냉각수 주의·로터 편차 경고
python tools/fake_vehicle.py --airframe quad    # 멀티콥터 (배터리·진동·무선)
```
GCS는 UDP 14550으로 자동 연결된다.

## 화면 구성 (비행 화면, 단일 모니터 콘솔)

```
┌ 메뉴 · 상태 · 모드 · [UAV 01][UAV 02][편대 명령] · (명령 확인) · 표시기 · UTC/KST ┐
│ 비행 계기              │ 지도 (QGC 지도 도구, 목표 조정 창)   │ 추진 · 추세        │
│ (FMA, PFD, 핵심 수치,  │                                       │ 전원·연료 · 경고   │
│  링크·항법)            ├ 고도 단면 ────────────────────────────┤ 미션               │
├ 진행 단계 · 명령 버튼 ─────────────────────────────── 비상 정지 (2초 누름) ─────────┤
```

- **디자인 원칙**: 짙은 흑연색 면과 얇은 구분선, 글꼴은 IBM Plex Sans KR(글) / IBM Plex Mono(숫자, `custom/res/fonts`, SIL OFL). 색은 의미에만 쓴다 — 하늘색: 경로·선택, **분홍: 목표값**(항공기 계기 관례), 초록: 동작 중인 모드, 노랑/빨강: 주의/경고.
- **위쪽 바** (`overrides/FlyViewToolBar.qml`): QGC 메뉴(로고), 기체 상태, 비행 모드 메뉴, 기체 탭(눌러서 선택), 편대 명령, QGC 명령 확인 슬라이더, 표시기, UTC/KST.
- **비행 계기** (`MLFlightColumn`): 모드 표시줄(SPD·LAT·VERT·MODE), PFD(자세, 속도·고도 테이프, 방위, 상승률, 분홍 목표 표시), V/S·AGL·TRK·홈 거리·다음 경유점·ETE, 링크·항법 막대.
- **고도 단면** (`MLProfile`): 미션 경로를 따라 고도, 경유점 아래 지형(있을 때), 현재 위치.
- **오른쪽** (`MLSystemsColumn`): 추진(엔진·로터 RPM 다이얼, 탠덤 동기 / 멀티콥터는 모터별 RPM), 최근 10분 추세선, 전원·연료, 경고(확인 버튼), 미션 목록(편집·다시 읽기).
- **목표 조정** (명령 바 [목표 조정]): ALT·SPD·HDG 목표값을 −/+(길게 누르면 반복)나 직접 입력으로 정하고 [보내기]를 두 번 누른다.
  - **미션 유지**: 남은 경유점 고도를 새 값으로 바꿔 미션을 다시 올리고 현재 경유점을 되돌려 놓는다(고도). 속도는 `DO_CHANGE_SPEED`. 기수는 그 방향 5 km 지점을 관심 지점(ROI)으로 지정해 경로는 그대로 날며 기수만 돌린다([기수 자동으로 되돌리기]로 해제).
  - **멈추고 변경**: 미션을 멈추고 그 자리에서 고도·기수를 바꾼다(ArduPilot GUIDED / PX4 Hold). 명령 바 [미션 재개]로 경로에 복귀.
- **명령 바**: 진행 단계와 다음 할 일, 단계에 맞는 버튼만 표시. 모든 명령은 두 번 눌러야 실행(첫 누름에 버튼이 켜지고 3초 안에 다시 누름). 비상 정지는 2초 누름.
- **자동 검증**: 빌드마다 ArduCopter SITL과 PX4 v1.16.2 SIH에 미션을 날리면서 GCS가 위 명령을 보내고, 별도 MAVLink 링크에서 기체가 따라 움직이는지 확인한다(`tools/ci_sitl.sh`, `tools/sitl_check.py`, 결과는 ci-screens 브랜치 `sitl-*.json`).
- 비상 정지(2초 누름): 엔진 데이터(EFI)가 있는 기체는 엔진 정지(`MAV_CMD_DO_ENGINE_CONTROL`), 그 외에는 QGC 모터 비상 정지.

## 현재 한계

- `tandem.json`의 경고 임계값은 **임시값**이다 (화면에 "임계값 임시" 표시). ICD·비행교범 확정 후 바꿔야 한다.
- 실제 기체·SITL(PX4/ArduPilot)로는 아직 시험하지 않았다. 화면 확인은 `tools/fake_vehicle.py`로만 했고, 이 시뮬레이터는 명령 실행(이륙·복귀 등)과 ESC(모터별 RPM) 데이터를 흉내 내지 않는다.
- VWorld 지도는 국내 IP에서만 열린다 (해외 서버인 자동 빌드 화면 캡처는 Esri 위성지도로 대체).
