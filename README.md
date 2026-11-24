# MobilityLab GCS

모빌리티랩 탠덤 무인헬기용 지상통제 프로그램(GCS). QGroundControl(QGC) v5.1.5를 기반으로, QGC 원본은 건드리지 않고 공식 커스텀 플러그인(`custom/`) 방식으로 만든다.

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
| `custom/qml/MobilityLab/Controls/` | 비행 화면 UI (탠덤 계통 패널, 마스터 경고등, 하단 명령 바) |
| `patches/` | QGC 원본에 대한 최소 수정 (VWorld 지도 레이어 이름 버그) |
| `tools/fake_vehicle.py` | 기체 없이 화면을 확인하는 가상 탠덤 헬기 (pymavlink) |
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
```
GCS는 UDP 14550으로 자동 연결된다.

## 화면 구성 (비행 화면)

- **오른쪽 위 · 탠덤 계통**: 전·후방 로터 RPM과 편차, 엔진·ECU, 동력전달(기어박스), 연료, 전원. 한 번도 수신되지 않은 항목은 숨기고, 수신되다 끊기면 "수신 끊김"으로 표시한다. 제목 줄을 누르면 접힌다.
- **위 가운데 · MASTER WARNING / CAUTION**: 경고·주의가 새로 생기면 깜박인다. 누르면 확인 처리되고, 상황이 해제될 때까지 목록은 남는다.
- **아래 · 명령 바**: ARM, 이륙, 미션 시작/재개, 일시정지, 복귀, 착륙. 모두 QGC 기본 확인 슬라이더를 거친다. 지금 쓸 수 없는 버튼은 흐리게 표시되고, 마우스를 올리면 이유가 나온다.
- **엔진 비상정지**: 2초간 누르고 있어야 `MAV_CMD_DO_ENGINE_CONTROL`(정지)을 보낸다. 펌웨어가 이 명령을 지원해야 동작한다.
- **다음 단계**: 연결 → ARM → 이륙/미션 순서에 맞춰 지금 할 일을 안내한다.
- 오른쪽 아래 자세·속도·고도 표시와 위쪽 상태 표시줄은 QGC 기본 기능을 그대로 쓴다.

## 현재 한계

- `tandem.json`의 경고 임계값은 **임시값**이다 (화면에 "임계값 임시" 표시). ICD·비행교범 확정 후 바꿔야 한다.
- FCC 펌웨어(PX4/ArduPilot)가 정해지지 않아 실제 기체·SITL로는 아직 시험하지 않았다. 화면 확인은 `tools/fake_vehicle.py`로만 했다.
- VWorld 지도는 국내 IP에서만 열린다 (해외 서버인 자동 빌드 화면 캡처는 Esri 위성지도로 대체).
