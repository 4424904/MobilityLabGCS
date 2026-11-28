# 시스템 요구 사항 (v1.2.0)

아래 "확인한 환경"은 실제로 실행해 본 환경, "권장"은 QGroundControl v5.1.5 와 Qt 6.10 기준으로 정한 값입니다. 권장 사양은 실측으로 정한 값이 아닙니다(실측 결과는 [PERFORMANCE.md](PERFORMANCE.md)).

| 항목 | 최소 / 권장 | 확인한 환경 |
|---|---|---|
| 운영체제 | Windows 10 21H2 이상 64비트 / **Windows 11** · Ubuntu **22.04 / 24.04** 64비트 | Windows Server 2022(GitHub Actions, 설치·실행·업그레이드·제거·영상 수신), Ubuntu 22.04·24.04(GitHub Actions, AppImage) |
| CPU | x86-64 4코어 / 6코어 이상 | GitHub Actions 표준 러너(4 vCPU) |
| 메모리 | 8 GB / 16 GB | 러너 16 GB |
| 그래픽 | OpenGL 3.3 이상(또는 Windows Direct3D 11) 지원 GPU / 외장·내장 GPU | **GPU 없는 소프트웨어 렌더링(llvmpipe)만 확인** — 실제 GPU 에서는 미확인 |
| 화면 | 1920×1080 / 1920×1080 이상, 듀얼 모니터 지원 | 가상 화면 1920×1080, 2560×1440, 3840×2160 |
| 디스크 | 설치 약 600 MB + 지도 캐시 + 비행 기록(시간당 약 수 MB) | — |
| 통신 | UDP(텔레메트리 기본 14550), 시리얼(텔레메트리 모뎀), 영상 UDP 5600(Windows) | SITL UDP, 내장 데모 |
| 인터넷 | 온라인 지도·지형 고도·업데이트 확인에 필요(없으면 캐시·평면 지형으로 동작) | — |

## 참고

* **영상(GStreamer)은 Windows 배포물에만 들어 있습니다.** Ubuntu AppImage 는 v1.0 부터 GStreamer 를 끈 구성이라 UDP/RTSP 영상 수신이 되지 않습니다(빌드 구성 문서 `BUILD.md`).
* Ubuntu 에서 AppImage 를 실행하려면 FUSE 가 필요합니다(`sudo apt install libfuse2` — 22.04, 24.04 는 `libfuse2t64`).
* 시리얼 텔레메트리 모뎀은 Ubuntu 에서 `dialout` 그룹 권한이 필요합니다.
* 설치 파일은 코드 서명이 없어 Windows Smart App Control / SmartScreen 이 막을 수 있습니다(설치·업데이트 안내 참고).
