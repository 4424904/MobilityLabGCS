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
┌ QGC 상태 표시줄 ─────────────────────────────────────────────────────┐
│ [비행계기][추진 계통][전원·연료][항법·통신][경고·알림]                │
│ ┌ 지도 (QGC 지도 도구·영상 포함) ─────────────┐ ┌ 미션 ───────────┐ │
│ └─────────────────────────────────────────────┘ └─────────────────┘ │
│ [진행 단계 · 다음 할 일][명령 버튼]                [시계][비상 정지] │
└──────────────────────────────────────────────────────────────────────┘
```

- **비행계기(PFD)**: 자세계, 속도·고도 테이프, 방위, 상승률. 제목 줄에 기체 종류·번호, 무장/안전 상태, 비행 모드. 고정익·VTOL 순항은 대기속도.
- **추진 계통**: 탠덤 헬기는 엔진·전방·후방 로터 RPM 원형 게이지, 탠덤 동기(Δrpm, 편차 %), 엔진·기어박스 값, 멀티콥터는 모터별 RPM(ESC 데이터). 해당 데이터가 없으면 칸이 빠지고 나머지 칸이 넓어진다.
- **전원·연료**: 배터리(여러 개면 각각), 연료 잔량·유량·체공 가능 시간, 보조 전원(데이터가 있을 때).
- **항법·통신**: 상태 목록(정상/주의/경고 점) — GPS, HDOP, 텔레메트리·조종기 신호 막대, 진동, 홈 거리, 비행 시간·거리.
- **경고·알림**: MASTER WARNING / CAUTION 램프와 경고 목록. 동력 계통 경고에 더해 통신 두절, 배터리 부족, GPS 미고정을 모든 기체에 대해 보여준다. 램프를 누르면 확인 처리된다.
- **미션**: 기체에 올라간 미션 목록(현재 지점 강조), 진행·다음 지점 거리·총 거리·예상 시간. 편집·업로드는 아래 버튼으로 QGC 계획 화면에서 한다.
- **명령 바**: 진행 단계(연결→준비→무장→비행→착륙)와 다음 할 일 안내. 지상에서는 ARM·이륙·미션 시작, 비행 중에는 일시정지(또는 미션 재개)·복귀·착륙만 보인다. **안전장치: 모든 명령 버튼은 두 번 눌러야 실행된다** — 첫 번째 누름에 버튼이 켜지고 "한 번 더 누르면 실행"과 3초 카운트다운이 나오며, 3초 안에 다시 누르면 명령이 나간다(시간이 지나면 취소). 이륙은 두 번째 누름 뒤 QGC 고도 선택 슬라이더가 뜬다.
- **비상 정지(2초 누르기)**: 엔진 데이터(EFI)가 있는 기체는 엔진 정지(`MAV_CMD_DO_ENGINE_CONTROL`), 그 외에는 QGC 모터 비상 정지.
- 레이아웃은 `custom/qml/overrides/FlyView.qml`(QGC 비행 화면 교체)에서 잡는다. 영상 전체 화면에서는 콘솔이 숨고 QGC와 같게 동작한다.

## 현재 한계

- `tandem.json`의 경고 임계값은 **임시값**이다 (화면에 "임계값 임시" 표시). ICD·비행교범 확정 후 바꿔야 한다.
- 실제 기체·SITL(PX4/ArduPilot)로는 아직 시험하지 않았다. 화면 확인은 `tools/fake_vehicle.py`로만 했고, 이 시뮬레이터는 명령 실행(이륙·복귀 등)과 ESC(모터별 RPM) 데이터를 흉내 내지 않는다.
- VWorld 지도는 국내 IP에서만 열린다 (해외 서버인 자동 빌드 화면 캡처는 Esri 위성지도로 대체).
