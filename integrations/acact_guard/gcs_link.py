"""
gcs_link.py — ACACT Guard ↔ MobilityLab GCS 연결
════════════════════════════════════════════════════════════════
가드 상태를 GCS 로 보내고 (5 Hz, UDP JSON), GCS 에서 온 운용 명령을 받는다.
가드의 판단·회피 로직(core.py)과는 무관하며, 이 연결이 끊겨도 가드는 그대로 동작한다.

  상태  : guard → GCS   UDP  GCS_STATUS_TARGETS (기본 127.0.0.1:47001)
  명령  : GCS → guard   UDP  0.0.0.0:GCS_CMD_PORT (기본 47002)
          {"cmd": "h", "id": 17, "from": "MobilityLabGCS"}
          허용 명령: h, r, g, g!, auto on|off, s  (load/start 는 GCS_ALLOW_LOAD_START=True 일 때만)
          GCS_CMD_ALLOW 에 없는 주소에서 온 명령은 버린다.
          받은 명령은 가드 화면·이벤트 로그에 "GCS 명령"으로 남는다.

GCS 가 다른 PC(Windows)에 있으면 환경변수로 지정:
  ACACT_GCS=192.168.1.20:47001  python3 guard.py --drones D1,D2
"""
import json
import os
import socket

import config as C

PROTO = 1


def _targets():
    v = os.environ.get("ACACT_GCS", "")
    out = []
    for part in [p.strip() for p in v.split(",") if p.strip()] or [f"{h}:{p}" for h, p in C.GCS_STATUS_TARGETS]:
        host, _, port = part.rpartition(":")
        try:
            out.append((host or "127.0.0.1", int(port)))
        except ValueError:
            pass
    return out


def _clean(v):
    """NaN/inf → None (GCS 쪽 JSON 파서가 NaN 을 받지 못함)"""
    if isinstance(v, float):
        return v if v == v and abs(v) != float("inf") else None
    if isinstance(v, dict):
        return {k: _clean(x) for k, x in v.items()}
    if isinstance(v, (list, tuple)):
        return [_clean(x) for x in v]
    return v


class GcsLink:
    def __init__(self, guard):
        self.g = guard
        self.targets = _targets()
        self.allow = set(C.GCS_CMD_ALLOW) | {h for h, _ in self.targets}
        self.tx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.rx = None
        self.ev_seq = 0
        self.ev = []            # [(seq, t, who, text)] 최근 40개
        try:
            self.rx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.rx.bind(("0.0.0.0", C.GCS_CMD_PORT))
            self.rx.setblocking(False)
        except OSError as e:
            print(f"※ GCS 명령 포트 {C.GCS_CMD_PORT} 를 열 수 없음 ({e}) — GCS 에서 명령은 못 보냄, 상태 표시는 됨")
            self.rx = None

    # ── 이벤트 (한국어 원문 그대로, 순번 포함) ──
    def on_event(self, t, who, text):
        self.ev_seq += 1
        self.ev = (self.ev + [(self.ev_seq, round(t, 1), who, text)])[-40:]

    # ── 상태 송신 ──
    def send(self, t, ins):
        g = self.g
        core = g.core
        site = None
        if g.frame is not None:
            site = {"lat": g.frame.lat0, "lon": g.frame.lon0, "bearing": g.site["bearing_deg"] if g.site else 0.0,
                    "radius": C.SCENARIO_RADIUS}
        by = {x.id: x for x in ins}
        drones = []
        for d in g.ds:
            x = by.get(d.id)
            o = core.own[d.id]
            item = {"id": d.id, "sysid": d.cfg["sysid"], "connected": d.connected,
                    "lat": d.lat, "lon": d.lon, "alt": round(d.rel_alt, 2),
                    "vn": round(d.vn, 2), "ve": round(d.ve, 2),
                    "mode": d.mode, "own": bool(o.owned), "yield": bool(o.yielding), "lock": bool(o.lock),
                    "fresh": bool(x.fresh) if x else False, "batt": d.batt,
                    "seq": d.cur, "total": d.total, "takeovers": o.takeovers}
            if x is not None and x.goal and g.frame is not None:
                glat, glon = g.frame.fr_to_ll(x.goal[0], x.goal[1])
                item["goal"] = [glat, glon]
            drones.append(item)
        pairs = []
        for (a, b), pe in core.pairs.items():
            ms = core.min_sep.get((a, b))
            pairs.append({"a": a, "b": b, "d": round(pe.d_now, 2), "dz": round(pe.dz, 2), "level": pe.level,
                          "cpa": round(pe.d_cpa, 2), "tcpa": round(pe.t_cpa, 2),
                          "min": round(ms, 2) if ms is not None and ms < 1e8 else None})
        msg = {"proto": PROTO, "src": "acact_guard", "t": round(t, 2),
               "auto": bool(g.auto), "loaded": list(g.loaded) if g.loaded else None,
               "cfg": {"d_safe": C.D_SAFE, "d_emerg": C.D_EMERG, "v_sep": C.V_SEP, "t_look": C.T_LOOK,
                       "rs": C.ACACT["rs"], "duo": C.DUO, "profile": C.PROFILE},
               "site": site, "drones": drones, "pairs": pairs,
               "events": [{"n": n, "t": tt, "who": w, "text": tx} for n, tt, w, tx in self.ev[-20:]]}
        data = json.dumps(_clean(msg), allow_nan=False, default=lambda o: None).encode()
        for tgt in self.targets:
            try:
                self.tx.sendto(data, tgt)
            except OSError:
                pass

    # ── 명령 수신 ──
    def poll(self):
        """새 명령을 꺼내 가드 명령 문자열 목록으로 돌려준다 (메인 루프에서 호출)."""
        out = []
        if self.rx is None:
            return out
        while True:
            try:
                data, addr = self.rx.recvfrom(4096)
            except (BlockingIOError, OSError):
                break
            if addr[0] not in self.allow and "*" not in self.allow:
                continue
            try:
                m = json.loads(data.decode())
                cmd = str(m.get("cmd", "")).strip()
            except Exception:
                continue
            head = cmd.split()[0].lower() if cmd else ""
            if head in ("h", "r", "g", "g!", "s") or (head == "auto" and cmd.lower() in ("auto on", "auto off")):
                out.append(cmd)
            elif head in ("load", "start") and C.GCS_ALLOW_LOAD_START:
                out.append(cmd)
            else:
                self.g.event("GCS", f"허용되지 않은 명령 무시: {cmd!r}")
        return out
