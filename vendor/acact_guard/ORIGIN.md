# ACACT Guard 원본 보존 (수정 금지)

| 폴더 | 원본 | 받은 날 | 비고 |
|---|---|---|---|
| `oregon_demo/` | `ACACT_Guard_오리건시연.zip` | 2026-11-26 | 오리건 시연 버전 |
| `rev1/` | `ACACT_Guard_오리건시연_수정1.zip` | 2026-11-26 | **GCS 이식 기준 버전**. 원본 저장소의 git 이력(`7405330 original file` → `7e6e11c Fix mission stall on sync release`)은 `archives/` 의 zip 안에 그대로 있음 |
| `archives/` | 받은 zip 파일 그대로 | | `SHA256SUMS` |

- 폴더 안 파일은 받은 그대로이며 고치지 않는다 (`__pycache__`, `.git` 만 제외). 무결성: 각 폴더의 `SHA256SUMS` (`sha256sum -c SHA256SUMS`).
- GCS 의 C++ 이식: `custom/src/acact/` (AcactCore = core.py, AcactScenarios = scenarios.py + geo.py, AcactConfig = config.py)
  와 `custom/src/MLAcactRuntime.*` (guard.py 의 운용 부분).
- 비교 검증: `tools/acact_verify/` — rev1 의 sim_check.py 를 그대로 돌리면서 매 스텝 원본 core.py 와 C++ 엔진을 같은 입력으로 비교.

## 오리건시연 → 수정1 변경 내용 (원본 비교 결과)

| 파일 | 변경 | GCS 반영 |
|---|---|---|
| `core.py` | 회피 중 통과점 도달 시 `_release_safe()` 로 미션 복귀 경로 안전 확인 후 복귀, 위험이 남으면 `ADVANCE_IN_AVOID` 에 따라 미션 순서만 넘기는 `advance` 명령 추가 | AcactCore `_releaseSafe`, `CmdKind::Advance` |
| `core.py` | 대기점 정착 판정 완화 (4 m/1.5 m/s → 6 m/2.5 m/s), 멀어지는 쌍(접근 속도 < -0.3 m/s) 무시 | AcactCore `evalPair` |
| `config.py` | `ADVANCE_IN_AVOID = False` 추가 | AcactConfig `advanceInAvoid` |
| `guard.py` | 동기 출발·advance 에 MAVSDK `set_current_mission_item` 대신 `MISSION_SET_CURRENT` 직접 1회 송신 + 진행 번호 확인(최대 3회), 건너뛰는 속도 변경은 직접 적용(`goto_next_item`) | MLAcactRuntime `_gotoNextItem` / `_setCurrent` |
| `guard.py` | 실제 HEARTBEAT 시스템 ID 사용, 지상 기수 방향 vs 설정 방위 30° 사전 점검 | MLAcactRuntime 사전 점검 |
| `scenarios.py` | 동기 대기 바로 뒤의 속도 변경을 대기 앞으로 옮김(`_speed_before_sync`); S7: 출발 간격 16→20 m, 추월 구간 속도 1.2→1.0 m/s·끝점 (12,0)→(6,0)/(24,4)→(28,4) | AcactScenarios |
| `plan_gen.py` | 방위 생략 시 기체 기수 방향 1초 평균으로 자동 (기체끼리 20° 넘게 다르면 중단) | MLAcactRuntime `setupSite` |
| `sim_check.py`, `stress_check.py` | advance 모사, 악조건 스트레스 시험 | 비교 검증에 그대로 사용 |
| `set_params.py`(확인 문구 기체 수), `launch_sitl.sh`, `demo.sh`(신규), `router/wifi*.conf`(신규) | PX4 파라미터·현장 절차 | GCS 범위 밖 (PX4 파라미터는 현장 절차서에서 관리) |

## GCS 에서 원본과 다르게 한 부분 (의도적, 판단 알고리즘은 동일)

| 항목 | 원본 guard.py | GCS | 이유 |
|---|---|---|---|
| 0 속도 설정점 미리 보내기 | 모든 기체에 상시 | 미션 비행 중이거나 가드가 비행 중인 기체에만 | PX4 는 Offboard 상실 페일세이프로 Hold 에 들어간 기체에 설정점이 다시 오면 OFFBOARD 로 되돌아감. 링크 복구·GCS 재시작 뒤 기체가 운용자 판단 없이 OFFBOARD 로 돌아가는 것을 SITL(gcskill, linkloss)에서 확인해 막음 |
| 운용자 명령 | QGC 와 별개 프로세스 | QGC 확인 버튼 명령이 가드 제어를 즉시 해제 | 같은 프로그램 안에서 제어 충돌 방지 |
| 사용자 미션 | 시나리오 .plan 만 | 임의 미션 + 비행 전 검사(AcactMissionCheck) | 요구사항 3 |
| 실비행/SITL 구분 | 없음 | 기체 판별, SITL 기록이 있어야 실비행 일괄 시작 | 요구사항 6 |
