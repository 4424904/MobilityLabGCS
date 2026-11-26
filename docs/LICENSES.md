# 오픈소스 라이선스

MobilityLab GCS 는 아래 구성요소로 만들어집니다. 배포물(설치 파일, 포터블, AppImage)에 들어가는 구성요소의 라이선스 원문은 최종 산출물의 `licenses/` 폴더에 들어 있습니다.

| 구성요소 | 버전 | 라이선스 | 비고 |
|---|---|---|---|
| QGroundControl | v5.1.5 | Apache-2.0 / GPL-3.0 (이중) | 원본 소스, `patches/` 로 최소 수정 |
| Qt (오픈소스) | 6.10 계열 | LGPL-3.0 (대부분), 일부 모듈 GPL-3.0 | 동적 링크. 사용 모듈별 라이선스는 Qt 문서 기준 |
| GStreamer (Windows 배포물) | QGC 지정 버전 | LGPL-2.1+ | 영상 수신 |
| SDL3, zstd, libusb 등 QGC 의존 라이브러리 | QGC v5.1.5 지정 | 각 라이선스 (zlib, BSD, LGPL 등) | QGC CPM 의존성 |
| MAVLink (C 헤더) | QGC 지정 | MIT | |
| IBM Plex Sans KR / Mono | — | SIL OFL 1.1 | `custom/res/fonts/OFL-IBM-Plex.txt` |
| ACACT 알고리즘·Guard (원본 Python, C++ 이식) | 수정1 | MobilityLab 소유 | Min & Nam, IEEE Access 2023 기반. 배포 범위는 회사 정책에 따름 |
| PX4 / ArduPilot | — | BSD-3 / GPL-3.0 | 배포물에 포함하지 않음 (CI 시험용으로만 내려받음) |

## 배포 전 확인할 점 (법률 검토 필요)

* QGroundControl 은 Apache-2.0 과 GPL-3.0 중 하나를 골라 쓸 수 있습니다.
* Qt 오픈소스판에는 GPL-3.0 전용 모듈(예: Qt Charts 등)이 있습니다. QGC v5.1.5 빌드가 이런 모듈을 쓰면, 배포물 전체에 GPL-3.0 조건(소스 공개 등)이 적용될 수 있습니다.
* 회사 소유 코드인 ACACT 엔진(`custom/src/acact`)을 비공개로 배포하려면, Qt 상용 라이선스 또는 모듈 구성 조정이 필요한지 **법률 검토를 받으세요.** 이 문서는 법률 자문이 아닙니다.
* LGPL 구성요소(Qt, GStreamer)는 동적 링크로 들어 있습니다. 사용자가 해당 라이브러리를 바꿔 끼울 수 있어야 하고, 라이선스 원문과 소스 입수 방법을 함께 제공해야 합니다.
