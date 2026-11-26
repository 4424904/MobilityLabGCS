# ACACT Guard ↔ MobilityLab GCS

GCS 에서 가드를 **켜고 끄고, 터미널 명령을 그대로 주고, 상태를 지도에서 봅니다.**
회피 판단은 그대로 `guard.py`(core.py)가 합니다. GCS 는 계산하지 않습니다.

```
            가드 노트북 (Ubuntu)                                     MobilityLab GCS (같은 PC 또는 Windows)
 guard_agent.py ── UDP 47003 ◀── 시작·종료·명령 한 줄·plan_gen ───── [가드 콘솔]
   └─ guard.py (stdin 은 에이전트가 쥠)
        └─ gcs_link.py ── UDP 47001 ── 상태 JSON 5 Hz ───────────▶ 지도 안전 반경·거리선, 편대 레인, 이벤트 기록
                        ◀─ UDP 47002 ── h/r/g/auto (에이전트 없이 가드만 켠 경우)
```

## 가드 노트북에 넣을 것 (1회)

```bash
cd ~/acact_guard
cp <이 폴더>/gcs_link.py <이 폴더>/guard_agent.py <이 폴더>/install_agent.sh .
patch -p1 < <이 폴더>/guard_gcs.patch      # guard.py · config.py 에 몇 줄 (core.py 변경 없음)
bash install_agent.sh                     # 로그인하면 에이전트 자동 실행
#   GCS 가 다른 PC(Windows)이면:  bash install_agent.sh --allow-lan
```

- 같은 PC 에서 GCS 를 쓰고 `~/acact_guard/guard_agent.py` 가 있으면, 에이전트가 안 떠 있어도 GCS 가 직접 띄웁니다.
- 에이전트는 가드를 자식으로 쥐고 있어서 GCS 를 꺼도 가드는 계속 돕니다. 에이전트가 죽으면 가드는 SIGINT 로 정상 종료(회피 중 기체 HOLD)합니다.
- 명령 허용 주소: 127.0.0.1, `ACACT_GCS`, `ACACT_AGENT_ALLOW`, (`--allow-lan` 이면 사설망 전체).
- mavlink-router(무전기 연결)나 SITL 은 지금처럼 따로 띄웁니다.

## GCS 에서

- 아래 편대 레인 오른쪽 **[가드 콘솔]**
  - 실행: 기체(D1,D2 — 연결된 기체에서 자동) · 프로파일 · [가드 시작] / [가드 종료]
  - "기체가 연결되면 가드를 자동으로 시작" (기본 켜짐, 세션당 1번)
  - 준비: 방위 · [미션 생성] (plan_gen --from-vehicles) · [파라미터 확인/적용]
  - 시나리오: 목록에서 고르고 demo/rehearsal · [불러오기] · [시작 (이륙)]
  - 진행: g · g! · r · 자동 진행 · s · 전체 HOLD
  - 터미널: guard.py 출력 그대로 + 직접 입력
- `시작`·`load`·`g` 처럼 기체를 움직이는 명령은 두 번 눌러야 나갑니다. 전체 HOLD 는 한 번.
- Windows 방화벽에서 MobilityLabGCS 의 UDP 를 허용해야 다른 PC 와 주고받습니다.
