# ACACT Guard — 원본 보존본 (수정 금지)

- 출처: 사용자(모빌리티랩 신승환) 제공 `ACACT_Guard______.zip`, 2026-11-26 수령
- 이 폴더의 파일은 받은 그대로이며 수정하지 않는다. 무결성: `SHA256SUMS`
  (`sha256sum -c SHA256SUMS` 로 확인)
- 용도
  1. 알고리즘 기준(reference): `tools/acact_compare` 가 이 코드의 sim_check 로 기준 궤적을 기록하고
     GCS 의 C++ 이식(`custom/src/acact/AcactCore.*`)이 같은 판단을 내리는지 매 빌드마다 비교한다.
  2. 현장에서 기존 방식(터미널 가드)으로 돌려야 할 때의 원본.
- 원본이 갱신되면: 새 폴더로 교체 → SHA256SUMS 갱신 → `docs/ACACT_INTEGRATION.md` 변경 이력에 기록 →
  C++ 이식에 같은 변경 반영 → 비교 통과 확인.
