"""
scenarios.py — 시연 시나리오 정의 (시연 프레임 F/R, m)
════════════════════════════════════════════════════════════════
각 기체 미션 = [공통 앞부분] + [시나리오 구간] + [공통 뒷부분]
  앞부분: 천천히 이륙(8 m) → 대기 → 앞으로 2 m → 대기 → 시작점으로 이동 → 동기 대기
          (시연 고도에서 경로가 엇갈리지 않으면 8 m 그대로, 엇갈리면 자기 층으로 올라가 이동 후 하강)
  뒷부분: 마지막 지점에서 자기 층으로 상승 → 이륙지점 상공 → 착륙
동기 대기(SYNC) = LOITER_UNLIM. 가드에서 'g' 를 누르면 4대가 동시에 다음 구간으로.
"""
import config as C

R = C.SCENARIO_RADIUS
IDS = [d["id"] for d in C.DRONES]
ALL_IDS = [d["id"] for d in C.ALL_DRONES]
LAYER = {d["id"]: d["layer"] for d in C.ALL_DRONES}


def home(did):
    lay = C.HOME_LAYOUTS.get(C.PROFILE)
    if lay:
        return lay[did]
    i = ALL_IDS.index(did)          # 일부 기체만 비행해도 자리는 4대 배치 기준
    return (C.HOME_LINE_F, (i - 1.5) * C.HOME_SPACING)


def step_pos(did):
    """이륙 후 앞으로 STEP_FWD 만큼 나간 지점"""
    h = home(did)
    return (h[0] + C.STEP_FWD, h[1])


def _assign(ids, slots):
    """기체 → 자리 배정: 이동거리 제곱합 최소 (경로가 서로 엇갈리지 않는 배정)"""
    import itertools
    best, bestc = None, 1e18
    keys = list(slots)
    for perm in itertools.permutations(keys, len(ids)):
        cost = 0.0
        for d, k in zip(ids, perm):
            p, q = step_pos(d), slots[k]
            cost += (p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2
        if cost < bestc:
            best, bestc = dict(zip(ids, perm)), cost
    return best


def direct_ok(starts, speed=None):
    """모든 기체가 시연 고도에서 출발점까지 직선으로 동시에 가도 서로 가까워지지 않는지 (간단 시뮬)"""
    speed = speed or C.LOW_TRANSIT_SPEED
    ids = list(starts)
    path = {}
    for d in ids:
        a, b = step_pos(d), starts[d]
        L = ((b[0] - a[0]) ** 2 + (b[1] - a[1]) ** 2) ** 0.5
        path[d] = (a, b, L)
    T = max(p[2] for p in path.values()) / speed + 1.0

    def at(d, t):
        a, b, L = path[d]
        k = 1.0 if L < 1e-6 else min(1.0, speed * t / L)
        return a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k
    for i in range(len(ids)):
        for j in range(i + 1, len(ids)):
            pa, pb = at(ids[i], 0), at(ids[j], 0)
            d0 = ((pa[0] - pb[0]) ** 2 + (pa[1] - pb[1]) ** 2) ** 0.5
            t = 0.0
            while t <= T:
                pa, pb = at(ids[i], t), at(ids[j], t)
                dd = ((pa[0] - pb[0]) ** 2 + (pa[1] - pb[1]) ** 2) ** 0.5
                if dd < min(d0, C.D_SAFE + 2.0) - 0.5:
                    return False
                t += 0.2
    return True


# 방위 약어 (F, R)
N_, S_, E_, W_ = (R, 0.0), (-R, 0.0), (0.0, R), (0.0, -R)   # N=전방, E=오른쪽


def wp(p, hold=0.0):
    return {"t": "wp", "p": p, "hold": hold}


def sync(p):
    return {"t": "sync", "p": p}


# ─────────────────────────────────────────────────────────────
# 시나리오별 정의: 시작점 + 시나리오 구간(고도는 공통 시나리오 고도)
# ─────────────────────────────────────────────────────────────
def _s1():
    # 편대 출격: 16 m 정사각 대형 유지하며 30 m 정사각 경로 1바퀴 (D_SAFE 10 m 보다 넓게)
    off = {"D1": (8, -8), "D2": (8, 8), "D3": (-8, -8), "D4": (-8, 8)}
    path = [(-15, -15), (15, -15), (15, 15), (-15, 15), (-15, -15)]
    out = {}
    for d, (of, orr) in off.items():
        pts = [(p[0] + of, p[1] + orr) for p in path]
        out[d] = {"start": pts[0], "legs": [wp(p) for p in pts[1:]]}
    return out


def _s2():
    # 정면 교차: 쌍 A(D1↔D3, 좌우축) 먼저, 쌍 B(D2↔D4, 전후축) 25초 뒤. 왕복.
    return {
        "D1": {"start": W_, "legs": [wp(E_, hold=30), wp(W_)]},
        "D3": {"start": E_, "legs": [wp(W_, hold=30), wp(E_)]},
        "D2": {"start": N_, "legs": [wp(N_, hold=25), wp(S_, hold=30), wp(N_)]},
        "D4": {"start": S_, "legs": [wp(S_, hold=25), wp(N_, hold=30), wp(S_)]},
    }


def _s3():
    # 4방향 중앙 동시 교차, 왕복 2회
    st = {"D1": W_, "D2": N_, "D3": E_, "D4": S_}
    op = {"D1": E_, "D2": S_, "D3": W_, "D4": N_}
    return {d: {"start": st[d], "legs": [wp(op[d], hold=10), wp(st[d])]} for d in st}


def _s4():
    # 거점 합류·포위: 2대씩 같은 관문으로 합류(순서대로 통과) → 목표 주위 14 m 링 배치(동기) → 링 1바퀴 회전
    rr = 14.0
    ring = {"N": (rr, 0), "W": (0, -rr), "S": (-rr, 0), "E": (0, rr)}
    order = ["N", "W", "S", "E"]           # 위에서 볼 때 반시계
    gate_w, gate_e = (0, -24), (0, 24)
    plan = {
        "D1": ((20, -34), gate_w, "N"),
        "D2": ((-20, -34), gate_w, "W"),
        "D3": ((20, 34), gate_e, "E"),
        "D4": ((-20, 34), gate_e, "S"),
    }
    out = {}
    for d, (st, gate, slot) in plan.items():
        k = order.index(slot)
        lap = [ring[order[(k + i) % 4]] for i in range(1, 5)]
        out[d] = {"start": st,
                  "legs": [wp(gate), wp(ring[slot]), sync(ring[slot])] + [wp(p) for p in lap]}
    return out


def _s5():
    # 구역 4분할 정찰: 60×60 m 를 4등분, 같은 패턴을 평행이동 → 4대가 같은 모양으로 동시 정찰
    base = [(4, 4), (4, 26), (11, 26), (11, 4), (18, 4), (18, 26), (25, 26), (25, 4)]
    org = {"D1": (0, -30), "D2": (0, 0), "D3": (-30, -30), "D4": (-30, 0)}
    out = {}
    for d, (of, orr) in org.items():
        pts = [(p[0] + of, p[1] + orr) for p in base]
        out[d] = {"start": pts[0], "legs": [wp(p) for p in pts[1:]]}
    return out


def _s6():
    # 통신 두절: 4대가 링 위 거점에서 대기 → 운용자가 1대 텔레메트리 차단 → PX4 RTL
    #   'g' (2번째) 로 나머지 복귀
    st = {"D1": W_, "D2": N_, "D3": E_, "D4": S_}
    return {d: {"start": p, "legs": [sync(p)]} for d, p in st.items()}


def _s0():
    """
    통합 1회 비행: S1 편대 → S3 4방향 교차 → S2 정면 교차 → S4 합류·포위 → (S6 통신 두절, 선택) → 귀환
    기동은 '역할'(편대 자리 FL/FR/BL/BR → 링 위치 N/E/W/S)로 정의하고,
    기체는 이륙 위치에서 가장 가까운 역할을 맡는다 → 이륙 후 시연 고도에서 서로 엇갈리지 않고 출발점으로 이동.
    2대만 비행하면 정면으로 마주치는 W·E 역할을 맡는다.
    """
    # 편대 자리 (16 m 정사각, 중심 (-6,0) → (14,0) 전진) 와 그 자리의 링 위치
    off = {"FL": (8, -8), "FR": (8, 8), "BL": (-8, -8), "BR": (-8, 8)}
    ring_of = {"FL": "N", "FR": "E", "BL": "W", "BR": "S"}
    P = {"N": N_, "E": E_, "W": W_, "S": S_}
    OPP = {"N": "S", "S": "N", "E": "W", "W": "E"}
    f0, f1 = (-6.0, 0.0), (14.0, 0.0)
    st = {k: (f0[0] + o[0], f0[1] + o[1]) for k, o in off.items()}
    fe = {k: (f1[0] + o[0], f1[1] + o[1]) for k, o in off.items()}
    # S4: N·W 는 북서 관문, E·S 는 남동 관문으로 합류 → 반경 14 m 포위 → 반 바퀴 회전
    gate = {"N": (12, -12), "W": (12, -12), "E": (-12, 12), "S": (-12, 12)}
    rr = 14.0
    slot = {"N": (rr, 0), "W": (0, -rr), "S": (-rr, 0), "E": (0, rr)}
    order = ["N", "W", "S", "E"]
    if len(IDS) == 4:
        role = _assign(IDS, st)
    else:
        pri = ["BL", "FR", "FL", "BR"][:len(IDS)]      # W, E, N, S 순
        role = _assign(IDS, {k: st[k] for k in pri})
    out = {}
    for d in IDS:
        fs = role[d]
        rg = ring_of[fs]
        k = order.index(rg)
        half = [slot[order[(k + i) % 4]] for i in (1, 2)]
        legs = [
            # ① S1 편대 전진
            wp(fe[fs]),
            # 편대 → 링 출발점 정렬 후 대기
            wp(P[rg]), sync(P[rg]),
            # ② S3 4방향 동시 교차 (1회)
            wp(P[OPP[rg]]), sync(P[OPP[rg]]),
            # ③ S2 정면 교차: E↔W 먼저, N↔S 는 12초 뒤
            wp(P[OPP[rg]], hold=12) if rg in ("N", "S") else wp(P[OPP[rg]]),
            wp(P[rg]), sync(P[rg]),
            # ④ S4 관문 합류 → 포위 배치
            wp(gate[rg]), wp(slot[rg]), sync(slot[rg]),
            #    반 바퀴 회전
        ] + [wp(p) for p in half] + [
            # ⑤ 거점 대기 (S6 통신 두절 시연은 이 상태에서 라우터 1개 종료)
            sync(half[-1]),
        ]
        out[d] = {"start": st[fs], "legs": legs}
    return out

def spd(v):
    return {"t": "speed", "v": v}


def _s7():
    """
    2대 역동 시나리오 (오리건 2대 시연용). 기동마다 대기점에서 4대 대신 2대가 동시에 출발.
      ① 편대 대시     : 16 m 간격 나란히 4 m/s 로 35 m 질주
      ② 고속 정면 교차 : 50 m 거리에서 서로 4.5 m/s 로 정면 돌진 (접근 속도 9 m/s)
      ③ 직각 교차     : 북→남, 서→동 으로 동시에 중앙 통과
      ④ 역방향 선회    : 바깥 원(21 m)·안쪽 원(15 m)을 서로 반대 방향으로 한 바퀴 — 두 번 스쳐 지나감
      ⑤ 추월          : 같은 줄에서 뒤 기체가 빠르게 따라붙어 오른쪽으로 비켜 추월
    2대 중 앞 번호가 A, 뒷 번호가 B.
    """
    ids = list(IDS)
    if len(ids) < 2:
        ids = ids + ["_"]
    A, B = ids[0], ids[1]
    import math
    RO = 21.0                                    # A 선회 반경 [m]
    circ = []
    for k in range(9):
        th = math.radians(-90 - 45 * k)          # A: 서쪽에서 시작해 남쪽(이륙선 쪽)을 지나 한 바퀴 (바깥 원, 오른쪽 = 바깥)
        circ.append((round(RO * math.cos(th), 2), round(RO * math.sin(th), 2)))
    RB = 15.0                                    # B 는 안쪽 원 (6 m 안쪽) — 마주칠 때 바깥/안쪽으로 엇갈림
    circ_b = [(round(f * RB / RO, 2), round(-r * RB / RO, 2)) for f, r in circ]   # B: 동쪽에서 시작, 반대 방향
    legs = {
        A: [
            spd(4.0), wp((15, -8)),
            spd(3.0), wp(W_), sync(W_),
            spd(4.5), wp(E_), sync(E_),
            spd(3.0), wp(N_), sync(N_),
            spd(4.0), wp(S_), sync(S_),
            spd(3.0), wp(circ[0]), sync(circ[0]),
            spd(3.0)] + [wp(p) for p in circ[1:]] + [sync(circ[-1]),
            spd(3.0), wp((0, 0)), sync((0, 0)),
            spd(1.2), wp((12, 0)), sync((12, 0)),
        ],
        B: [
            spd(4.0), wp((15, 8)),
            spd(3.0), wp(E_), sync(E_),
            spd(4.5), wp(W_), sync(W_),
            spd(3.0), wp(W_), sync(W_),
            spd(4.0), wp(E_), sync(E_),
            spd(3.0), wp(circ_b[0]), sync(circ_b[0]),
            spd(3.0)] + [wp(p) for p in circ_b[1:]] + [sync(circ_b[-1]),
            spd(3.0), wp((-20, 4)), sync((-20, 4)),
            spd(4.0), wp((24, 4)), sync((24, 4)),
        ],
    }
    starts = {A: (-20, -8), B: (-20, 8)}
    return {d: {"start": starts[d], "legs": legs[d]} for d in IDS if d in (A, B)}


SCENARIOS = {
    "S7_duo": ("2대 역동 시나리오 (편대 대시·고속 정면·직각·역선회·추월)", _s7),
    "S0_integrated": ("통합 1회 비행 (S1→S3→S2→S4→S6)", _s0),
    "S1_formation": ("편대 출격", _s1),
    "S2_headon": ("정면 교차 (2쌍 순차)", _s2),
    "S3_cross4": ("4방향 중앙 동시 교차", _s3),
    "S4_merge": ("거점 합류·포위", _s4),
    "S5_survey": ("구역 4분할 정찰", _s5),
    "S6_linkloss": ("통신 두절 대응", _s6),
}


def available(name: str) -> bool:
    """S7_duo 는 2대 전용, 나머지는 2~4대"""
    if name == "S7_duo":
        return len(IDS) == 2
    return True


def build(name: str, mode: str = "demo"):
    """
    mode = "demo"      : 시나리오 구간 고도 = DEMO_ALT (4대 동일 → 실제 회피 발생)
    mode = "rehearsal" : 시나리오 구간 고도 = 기체별 층 고도 (서로 수직 분리)
    return {id: [item...]}  item: takeoff / speed / wp / sync / land (F,R,alt)
    """
    _, fn = SCENARIOS[name]
    sc = fn()
    direct = mode == "demo" and direct_ok({d: sc[d]["start"] for d in IDS})
    out = {}
    for d in IDS:
        lay = LAYER[d]
        alt = C.DEMO_ALT if mode == "demo" else lay
        h = home(d)
        s = sc[d]["start"]
        f = step_pos(d)
        # ① 천천히 이륙 (TAKEOFF_ALT) → 대기 → ② 앞으로 STEP_FWD → 대기
        items = [
            {"t": "takeoff", "p": h, "alt": C.TAKEOFF_ALT},
            {"t": "sync", "p": h, "alt": C.TAKEOFF_ALT},
            {"t": "speed", "v": C.LOW_TRANSIT_SPEED},
            {"t": "wp", "p": f, "alt": C.TAKEOFF_ALT, "hold": 0},
            {"t": "sync", "p": f, "alt": C.TAKEOFF_ALT},
        ]
        # ③ 출발점으로 이동: 시연 고도에서 서로 엇갈리지 않으면 그 고도로 바로, 아니면 자기 층으로 올라가서
        if direct and alt == C.TAKEOFF_ALT:
            # 뒷줄 기체는 3초 늦게 출발 → 앞줄 뒤를 따라가며 간격이 줄지 않음
            maxf = max(step_pos(x)[0] for x in IDS)
            if f[0] < maxf - 5.0:
                items += [{"t": "wp", "p": f, "alt": alt, "hold": 3.0}]
            items += [{"t": "wp", "p": s, "alt": alt, "hold": 0}]
        else:
            # 4대가 모두 자기 층에 올라간 뒤 수평 이동 (먼저 올라간 기체가 아직 상승 중인 옆 기체 고도를 지나가지 않도록)
            items += [{"t": "wp", "p": f, "alt": lay, "hold": 0},
                      {"t": "sync", "p": f, "alt": lay},
                      {"t": "speed", "v": C.TRANSIT_SPEED},
                      {"t": "wp", "p": s, "alt": lay, "hold": 0}]
            if alt != lay:
                items.append({"t": "wp", "p": s, "alt": alt, "hold": 0})
        items += [{"t": "sync", "p": s, "alt": alt, "tag": "start"},
                  {"t": "speed", "v": C.SCENARIO_SPEED}]
        last = s
        for leg in sc[d]["legs"]:
            it = dict(leg)
            if "p" in leg:
                it["alt"] = alt
                last = leg["p"]
            items.append(it)
        # 동기 #Z: 자기 층으로 상승 후 대기 → 4대 모두 수직 분리 확인 → 'g' → 귀환
        items.append({"t": "wp", "p": last, "alt": lay, "hold": 0})
        items.append({"t": "sync", "p": last, "alt": lay, "tag": "end"})
        # 귀환: 자기 층 고도로 이륙지점 상공까지 → 대기(4대 모두 도착 확인) → 'g' → 동시 수직 착륙
        #   (먼저 온 기체가 내려가며 다른 기체의 이동 고도를 가로지르지 않도록)
        items += [{"t": "speed", "v": C.TRANSIT_SPEED},
                  {"t": "wp", "p": h, "alt": lay, "hold": 0},
                  {"t": "sync", "p": h, "alt": lay},
                  {"t": "land", "p": h, "alt": 0}]
        out[d] = items
    return out
