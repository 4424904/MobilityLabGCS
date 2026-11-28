# 설치 · 업데이트 · 복구 안내 (v1.2.0)

## 1. 새로 설치

| 배포물 | 방법 |
|---|---|
| Windows 설치형 `MobilityLabGCS-1.2.0-Windows-Setup.exe` | 실행 → 안내대로 설치. 바탕화면·시작 메뉴 바로가기가 생깁니다. |
| Windows 포터블 `MobilityLabGCS-1.2.0-Windows-Portable.zip` | 원하는 폴더에 압축을 풀고 `bin\MobilityLabGCS.exe` 실행. 설정·기록은 그 폴더의 `data\` 에 저장됩니다(USB 메모리에서도 사용 가능). |
| Ubuntu `MobilityLabGCS-1.2.0-Ubuntu-x86_64.AppImage` | `chmod +x MobilityLabGCS-1.2.0-Ubuntu-x86_64.AppImage` 후 실행. |

받은 파일은 릴리스의 `SHA256SUMS.txt` 와 비교할 수 있습니다: Windows PowerShell `Get-FileHash 파일 -Algorithm SHA256`, Ubuntu `sha256sum -c SHA256SUMS.txt --ignore-missing`.

### Windows 가 설치 파일을 막을 때 (코드 서명 없음)

* "Windows의 PC 보호"(SmartScreen) → **추가 정보 → 실행**.
* "스마트 앱 컨트롤이 차단" → 받은 파일 오른쪽 클릭 → **속성 → 맨 아래 "차단 해제" 체크 → 확인** 후 다시 실행. 그래도 막히면 Windows 보안 → 앱 및 브라우저 컨트롤 → 스마트 앱 컨트롤 설정에서 끌 수 있습니다(끄면 다시 켤 수 없으니 회사 보안 정책을 확인하세요).
* 근본 해결은 코드 서명 인증서(유료)입니다 — 이번 버전에는 적용하지 않았습니다.

## 2. v1.1.0 / v1.0.0 에서 업데이트

* **기체가 모두 꺼진 상태에서** 새 설치 파일을 그대로 실행하면 됩니다. 이전 버전을 먼저 지울 필요가 없습니다.
* 유지되는 것: 사용자 설정(화면 배치·모드·즐겨찾기·단축키·QGC 설정), 미션 파일, ACACT 기록, 지도 캐시. CI 에서 v1.1.0-build.96 을 설치·사용한 뒤 v1.2.0 을 덮어 설치해 설정·미션·기록이 남는지 확인합니다(Windows Server 2022).
* 업데이트 전에 **환경 설정(⚙) → 백업 · 진단 · 업데이트 → 백업** 으로 설정을 .ini 파일로 저장해 두는 것을 권합니다.
* 이전 버전으로 되돌리기: 이전 릴리스(v1.1.0-build.96 등)의 설치 파일을 다시 설치합니다. 설정은 그대로 남지만 v1.2 에만 있는 설정 항목은 무시됩니다.

## 3. 프로그램 안에서 업데이트 확인

환경 설정(⚙) → 백업 · 진단 · 업데이트 → **확인**.

1. GitHub 릴리스에서 최신 버전 번호만 조회합니다(자동으로 받지 않음, 개인정보 전송 없음).
2. 새 버전이 있으면 **릴리스 보기**로 변경 사항을 먼저 확인합니다.
3. (Windows 설치형만) **받기 · 검증** → 설치 파일과 `SHA256SUMS.txt` 를 받아 체크섬이 일치할 때만 설치 버튼이 켜집니다. 불일치하면 받은 파일을 지웁니다.
4. **설치(GCS 종료)** — 시동이 걸렸거나 비행 중인 기체가 있으면 거부합니다.

시험판(Pre-release)도 "새 버전"으로 안내되며 버전 옆에 "시험판 · 실기체 검증 전"이 붙습니다.

## 4. 문제가 생겼을 때

* **비정상 종료 후 다시 켰을 때** 안내가 나옵니다. 비행 기록은 2 Hz 로 계속 파일에 쓰므로 종료 직전까지 남아 있습니다.
* **진단 보고서**: 환경 설정 → 진단 보고서 → 만들기. 버전·OS·화면·설정 목록을 텍스트 파일로 저장합니다(키·토큰·좌표·즐겨찾기 값은 지움). 문제 보고 때 이 파일을 보내세요.
* **설정 복원**: 환경 설정 → 복원… → 백업 .ini 선택 → 프로그램을 다시 시작하면 적용됩니다. 시동이 걸린 기체가 있으면 복원하지 않습니다.
* **설정 초기화**: 프로그램을 닫고 Windows `%APPDATA%\MobilityLab\` (Ubuntu `~/.config/MobilityLab/`) 폴더 이름을 바꾸면 처음 상태로 시작합니다. 비행 기록(문서\MobilityLab\Records)은 지워지지 않습니다.

## 5. 데이터 위치

| 데이터 | Windows 설치형 | 포터블 | Ubuntu |
|---|---|---|---|
| 설정 | `%APPDATA%\MobilityLab\MobilityLabGCS.ini` | `data\` | `~/.config/MobilityLab/` |
| 비행 기록 (실비행·SITL / 데모 분리) | `문서\MobilityLab\Records\Flights`, `…\Demo` | `data\Records\…` | `~/Documents/MobilityLab/Records/…` |
| ACACT 가드 기록 | `문서\MobilityLab\ACACT` | `data\…` | `~/Documents/MobilityLab/ACACT` |

비행 기록 위치는 기록 화면(Ctrl+Shift+L)에서 바꿀 수 있습니다(기록 중에는 불가). 제거 프로그램은 설정과 기록을 지우지 않습니다.
