# 빌드 안내

MobilityLab GCS 는 QGroundControl **v5.1.5** 소스에 이 저장소를 얹어서 빌드합니다. QGC 원본은 받은 그대로 두고, 바꾸는 부분은 커스텀 플러그인 `custom/`, 작은 패치 `patches/`, 설치 스크립트 보정으로 한정합니다.

## 1. 가장 쉬운 방법: GitHub Actions

저장소에 push 하면 `.github/workflows/build.yml` 이 아래를 모두 만듭니다. Actions 탭의 실행 결과에서 Artifacts 로 받을 수 있습니다.

| 산출물 | Artifact 이름 |
|---|---|
| Ubuntu AppImage | `MobilityLabGCS-Ubuntu-AppImage` |
| Windows 설치 파일 | `MobilityLabGCS-Windows-installer` |
| Windows 포터블 zip | `MobilityLabGCS-Windows-portable` |
| 시험 결과 | `screens-*` (그리고 `ci-screens`, `ci-windows` 브랜치) |

## 2. 직접 빌드: 공통 준비

```bash
git clone --branch v5.1.5 --depth 1 --recurse-submodules https://github.com/mavlink/qgroundcontrol.git qgc
cd qgc
git clone https://github.com/4424904/MobilityLabGCS.git mlgcs
bash mlgcs/tools/ci_prepare.sh     # custom/ 복사, patches 적용, 한국어 보충, Windows 설치 스크립트 보정
```

* Qt **6.10.x** 가 필요합니다. QGC v5.1.5 가 요구하는 버전으로, CI 는 aqtinstall 로 설치합니다.
* 모듈: qtcharts, qtlocation, qtpositioning, qtspeech, qtmultimedia, qtserialport, qtimageformats, qtshadertools, qtconnectivity, qtquick3d, qtsensors, qtscxml.
* CMake 3.25 이상, Ninja, Python 3 도 필요합니다.

## 3. Ubuntu 22.04 / 24.04

```bash
sudo apt install build-essential ninja-build ccache pkgconf patchelf file desktop-file-utils libfuse2 \
  libxkbcommon-x11-dev libxcb-cursor-dev libegl-dev libgl-dev libusb-1.0-0-dev libspeechd-dev
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=<Qt>/gcc_64 \
  -DQGC_CREATE_APPIMAGE=ON -DQGC_BUILD_INSTALLER=ON -DQGC_ENABLE_GST_VIDEOSTREAMING=OFF
cmake --build build
APPIMAGE_EXTRACT_AND_RUN=1 cmake --install build      # → build/MobilityLabGCS-x86_64.AppImage
```

* AppImage 는 Ubuntu 22.04 에서 빌드합니다. 오래된 glibc 에서 빌드해야 22.04 와 24.04 모두에서 실행됩니다.
* 이 빌드는 영상(GStreamer)을 끈 구성입니다. 영상이 필요하면 GStreamer 개발 패키지를 설치하고 `QGC_ENABLE_GST_VIDEOSTREAMING=ON` 으로 빌드하세요. 이 구성은 CI 에서 검증하지 않았습니다.

## 4. Windows 10/11 (x64)

1. Visual Studio 2022 (C++ 데스크톱), Qt 6.10 msvc2022_64, CMake, Ninja, NSIS 3, Python 3 을 설치합니다.
2. "x64 Native Tools Command Prompt" 에서 아래를 실행합니다.

```bat
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=C:\Qt\6.10.x\msvc2022_64 ^
  -DQGC_ENABLE_GST_VIDEOSTREAMING=ON
cmake --build build
cmake --install build          :: → build\MobilityLabGCS-installer-*.exe (Qt·MSVC 런타임·GStreamer 포함)
```

포터블 zip 은 설치된 폴더를 복사하고, 맨 위에 `portable.txt` 를 두고, 제거 프로그램을 지운 것입니다. 만드는 절차는 `tools/win_package_test.ps1` 에 있습니다.

## 5. 검증 도구

* `bash tools/acact_verify/run.sh /tmp/v`
  * 원본 ACACT(rev1) ↔ C++ 엔진 동등성 비교
  * 시나리오·좌표 비교
  * 미션 검사 회귀 시험
  * 필요한 것: Python 3, numpy, g++
* `bash tools/acact_verify/analysis_test.sh <Qt 경로> /tmp/a`: 분석·PDF 회귀 시험
* `python3 tools/i18n_extract.py`: 영어 번역 누락 검사
* `bash tools/ci_sitl.sh <AppImage> <출력> <PX4 SITL 폴더> <case>`: SITL 시험
  * case 는 targets, s7duo, preflight, user, gcskill, linkloss, operator 중 하나
  * 필요한 것: Xvfb, xdotool, pymavlink. linkloss 는 iptables(sudo)도 필요합니다.

## 6. 의존성과 버전

| 항목 | 버전 |
|---|---|
| QGroundControl | v5.1.5 (`QGC_REF`) |
| Qt | 6.10 계열 (QGC v5.1.5 기준, `.github/actions/build-setup`) |
| PX4 (SITL 시험) | v1.16.2 (`PX4_REF`) |
| ArduCopter (SITL 시험) | firmware.ardupilot.org stable |
| ACACT 원본 | ACACT_Guard_오리건시연_수정1 (rev1) — `vendor/acact_guard/ORIGIN.md` |
| MobilityLab GCS | `custom/ML_VERSION.txt` |
