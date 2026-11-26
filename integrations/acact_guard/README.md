# ACACT Guard — GCS 내장

가드(`src/`, 신승환 작성 코드 + GCS 연동 몇 줄)는 **MobilityLab GCS 안에서 실행됩니다.**
따로 가드를 켜거나 터미널에 입력할 필요가 없습니다. Windows / Linux 모두.

```
MobilityLab GCS ─┬─ 기체 링크 (무전기·UDP·SITL)  ── 기체 1…4
                 ├─ 중계: 기체 n 메시지 ⇄ 127.0.0.1:1454n  (mavlink-router 역할)
                 │        └─ guard.py 의 mavsdk_server (D1…D4)
                 ├─ guard.py / plan_gen.py / set_params.py 실행 (stdin·stdout 을 GCS 가 쥠)
                 └─ 가드 상태 수신 UDP 47001 → 지도 안전 반경·거리선, 편대 레인, 이벤트 기록
```

- **Windows 설치파일**에 전용 파이썬(3.12 + mavsdk + numpy)과 가드 코드가 들어 있습니다.
  처음 실행할 때 가드 코드는 `%LOCALAPPDATA%\MobilityLab\…\acact_guard` 로 복사되고
  (plans/, logs/, site.json 이 여기에 생김) GCS 업데이트 때 바뀐 파일만 갱신됩니다.
- **Linux**: `~/acact_guard` 가 있으면 그것을, `~/acact-venv` 파이썬으로 실행합니다.
  (`ACACT_GUARD_DIR`, `ACACT_PYTHON` 환경변수로 바꿀 수 있음)
- GCS 가 기체를 가드에 직접 중계하므로 mavlink-router 는 필요 없습니다.
  이미 mavlink-router 로 연결하는 환경이면 가드 콘솔에서 "직접 중계"를 끄세요.
- GCS 가 종료되면 가드도 함께 종료됩니다 → mavsdk_server 가 멈추고 PX4 는 Offboard 상실 시 Hold.

## GCS 에서 (아래 편대 레인 → [가드 콘솔])

1. 기체 연결 → 가드 자동 시작 (끌 수 있음)
2. 준비: 방위 → [미션 생성] (plan_gen --from-vehicles), [파라미터 확인/적용]
3. 시나리오 선택 · demo/rehearsal → [불러오기] → [시작 (이륙)]
4. 진행: 다음 단계 g · g! · 재개 r · 자동 진행 · 상태 s · 전체 HOLD h
5. 터미널: 가드 출력 그대로, 직접 입력도 가능

기체를 움직이는 명령은 두 번 눌러야 나갑니다. 전체 HOLD 는 한 번.

## 원격 가드 (선택)

가드를 다른 Ubuntu PC 에서 돌리고 싶으면 그 PC 에서 `src/install_agent.sh --allow-lan`.
GCS 에 내장 가드가 없을 때만 에이전트를 찾습니다.
