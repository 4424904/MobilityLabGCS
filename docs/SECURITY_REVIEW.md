# 보안 · 라이선스 검토 (v1.2.0)

검토일 2026-11-28 · 대상: 저장소 `4424904/MobilityLabGCS`(dev-1.2 브랜치)와 v1.2.0 릴리스 파일.
저장소 공개 범위는 바꾸지 않았습니다. 아래 **조치 권고**는 회사가 결정할 사항입니다. 이 문서는 법률 자문이 아닙니다.

## 1. 결론 요약

| # | 항목 | 상태 | 조치 |
|---|---|---|---|
| S1 | 저장소가 **공개(Public)** 이고 라이선스 파일이 없음 | 위험 | 회사 결정 필요 (아래 2장) |
| S2 | 회사 소스코드가 공개 저장소에 있음: ACACT C++ 엔진 `custom/src/acact`, 원본 ACACT Guard(Python) `vendor/acact_guard/` (rev1, oregon_demo) | 위험 | 공개 범위 변경은 하지 않았음. 회사 결정 필요 |
| S3 | v1.0·v1.1 릴리스에 `source.zip`(위 코드 포함)과 `changes-vs-QGC.zip` 첨부 | 위험 | **v1.2 부터 소스 압축 파일을 첨부하지 않음**(`tools/make_deliverables.sh`). 이전 릴리스는 지시대로 삭제·수정하지 않음 |
| S4 | API 키·토큰 | 이상 없음 | VWorld 키는 소스에 없음(빌드 옵션 `-DML_VWORLD_KEY` 또는 사용자 입력). CI 의 `GH_TOKEN` 은 GitHub 가 실행마다 발급하는 임시 토큰 |
| S5 | 실제 비행 기록 | 이상 없음 | 저장소의 `vendor/acact_guard/rev1/logs/*.csv`(2026-11-03, 10개)는 SITL/시뮬레이터 기록(고도 ≈0 m, HOLD). 실비행 ULog·tlog 없음 |
| S6 | 위치 정보 | 주의 | 데모·SITL 기본 위치 37.2100856, 126.8307462 (화성 드론비행시험센터, 공개 시설). `vendor/` 의 오리건 실증 시나리오와 CLAUDE.md 에 실증 계획(오리건, 화성 리허설)이 적혀 있음 |
| S7 | 내부 설정 | 주의 | `vendor/acact_guard/rev1/router/wifi*.conf` 에 기체 Wi-Fi 브리지 설정 예시(사설 IP 192.168.x) — 비밀번호 없음 |
| S8 | v1.2 새 기능이 만드는 파일 | 이상 없음 | 비행 기록·진단 보고서·설정 백업은 사용자 PC(문서 폴더 등)에만 저장, 저장소·릴리스에 들어가지 않음. 진단 보고서는 키·토큰·좌표·즐겨찾기 값을 지움 |
| S9 | 업데이트 확인 | 이상 없음 | GitHub 공개 API 에 버전 조회만 함(개인정보 전송 없음). 사용자 동의 후 받기, SHA256 일치할 때만 설치, 시동/비행 중 설치 거부 |
| L1 | **Qt GPL-3.0 전용 모듈** — QGC v5.1.5 가 Qt Quick 3D, Qt Graphs, Qt HttpServer 를 링크함 | 위험(법률) | 아래 3장 |

## 2. 공개 저장소에 대한 권고 (S1–S3, S6–S7)

* 지금 상태로는 누구나 ACACT 엔진·Guard 원본과 시험 시나리오를 내려받을 수 있습니다(저장소 + 이전 릴리스 `source.zip` + GitHub 가 공개 릴리스마다 자동으로 붙이는 "Source code" 압축).
* 선택지 (회사 결정):
  1. 저장소를 비공개로 전환 — 비공개 저장소의 GitHub Actions 는 무료 사용 시간 제한이 있어(Windows 빌드는 시간이 2배로 계산), 지금 빌드량이면 유료가 될 수 있습니다. 그래서 이번에는 바꾸지 않았습니다.
  2. 공개 저장소에는 GCS(UI) 만 두고 ACACT 엔진은 별도 비공개 저장소/비공개 라이브러리로 분리 — 아래 3장의 GPL 문제가 함께 걸립니다.
  3. 공개 유지(현재) — 회사가 ACACT 소스 공개를 받아들이는 경우.
* 이미 공개된 이력(git 기록, 이전 릴리스 첨부물, 포크·캐시)은 비공개로 바꿔도 회수되지 않습니다.
* 이전 릴리스(v1.0, v1.1)의 `source.zip` 삭제 여부도 회사 결정 사항입니다(지시에 따라 건드리지 않음).

## 3. 라이선스 검토 (L1)

* QGC v5.1.5 는 Apache-2.0/GPL-3.0 이중 라이선스이고, 링크하는 Qt 모듈 중 **Qt Quick 3D · Qt Graphs · Qt HttpServer 는 Qt 오픈소스판에서 GPL-3.0(또는 상용)** 입니다. MobilityLab GCS 의 3D 화면도 Qt Quick 3D 를 씁니다.
* 따라서 오픈소스 Qt 로 빌드한 배포물(v1.0–v1.2 모두)은 GPL-3.0 조건을 따라야 할 가능성이 높습니다: 배포받은 사람에게 **대응 소스(ACACT 엔진 포함)를 제공할 의무**가 생길 수 있습니다. 저장소가 공개인 지금은 소스를 구할 수 있는 상태입니다.
* 소스를 비공개로 하려면 (a) Qt 상용 라이선스, 또는 (b) GPL 전용 모듈을 빼는 구성(QGC 3D 뷰어·그래프 기능 제거 — "QGC 기능 삭제 금지" 지시와 충돌)이 필요한지 **법률 검토를 받으세요.**
* 지도·지형 데이터:
  * 위성 영상 기본값 Esri World Imagery(키 불필요) — Esri 이용 약관과 출처 표시 조건을 따릅니다. 대량 다운로드·오프라인 저장은 약관 제한이 있을 수 있어 **오프라인 지도 받기는 제공자 약관을 확인한 뒤** 쓰세요.
  * VWorld — 국토교통부 공간정보 오픈플랫폼 약관(키 필요, 국내 IP).
  * 지형 고도 — QGC 기본 제공자 Copernicus DEM(Auterion 이 운영하는 terrain-ce.suite.auterion.com 경유). Copernicus DEM 은 출처 표시 조건이 있고, 약 30 m 격자의 **표면 모델(DSM — 건물·수목 높이 포함)**이라 **3D 지형은 시각화 전용**으로 표시하고 안전 판단에 쓰지 않습니다.
  * 건물 데이터 — 라이선스가 확인된 무료 출처를 쓰지 않았으므로 **넣지 않았습니다**(화면에 "건물 데이터 없음" 표시). 임의 생성 건물 없음.
* 글꼴 IBM Plex(SIL OFL 1.1), MAVLink(MIT), GStreamer(LGPL-2.1+) — 원문을 `licenses/` 에 동봉.

## 4. 점검 방법 (재현)

```bash
git grep -nIiE "(api[_-]?key|secret|token|password|BEGIN (RSA|OPENSSH|PRIVATE)|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,})"
git ls-files | grep -iE "\.(ulg|tlog|csv|kml|plan|db|sqlite|log)$"
git grep -nE "3[0-9]\.[0-9]{6,}"                       # 좌표
git grep -nIE "192\.168\.|@[a-z0-9-]+\.(com|kr)"        # 내부 주소·메일
```
QGC 링크 모듈: QGC v5.1.5 `CMakeLists.txt`, `src/**/CMakeLists.txt` 의 `Qt6::*` 대상.
