# ACACT Guard ↔ MobilityLab GCS 연결

ACACT Guard(`guard.py`)는 그대로 노트북에서 회피 판단을 하고, GCS는 그 상태를 **보여주고 명령만 보냅니다.**
GCS가 회피를 계산하지는 않습니다.

```
기체(PX4) ── mavlink-router ──┬── guard.py ──(상태 JSON 5 Hz, UDP 47001)──▶ MobilityLab GCS
                              │       ▲                                      (지도 위 안전 반경·거리선,
                              │       └──(명령 h/r/g/auto, UDP 47002)───────   편대 레인, 이벤트 기록)
                              └── UDP 14550 ─────────────────────────────▶ MobilityLab GCS (기체 텔레메트리)
```

## 가드 쪽 적용 (1회)

```bash
cd ~/acact_guard
cp <이 폴더>/gcs_link.py .
patch -p1 < <이 폴더>/guard_gcs.patch      # guard.py · config.py 에 몇 줄 추가 (core.py 변경 없음)
```

- 상태 전송: `config.py` 의 `GCS_STATUS_TARGETS` (기본 같은 PC `127.0.0.1:47001`).
  GCS 가 다른 PC(Windows)이면 `ACACT_GCS=192.168.x.x:47001 python3 guard.py --drones D1,D2`
- 명령 수신: UDP 47002. `GCS_CMD_ALLOW` 에 있는 주소(와 ACACT_GCS 주소)에서 온 것만 받습니다.
- GCS 에서 보낼 수 있는 명령: `h`(전체 HOLD), `r`(재개), `g`(다음 단계), `auto on/off`.
  `load`·`start` 는 현장 절차대로 가드 터미널에서만 (`GCS_ALLOW_LOAD_START = False`).
- GCS 에서 온 명령은 가드 화면과 이벤트 로그에 `GCS 명령: …` 으로 남습니다.
- 연결이 끊겨도 가드 동작에는 영향이 없습니다. 기존 `guard_map.py` 도 그대로 씁니다.

## GCS 쪽

- 가드가 실행되면 자동으로 연결됩니다 (아래 편대 레인 머리줄 `ACACT GUARD` 점이 초록).
- 포트를 바꾸려면 GCS 실행 전에 환경변수 `ML_GUARD_PORT`, `ML_GUARD_CMD_PORT`.
- Windows 방화벽에서 MobilityLabGCS 의 UDP 수신을 허용해야 다른 PC 의 가드 상태가 들어옵니다.
