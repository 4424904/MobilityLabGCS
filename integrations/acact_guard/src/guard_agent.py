#!/usr/bin/env python3
"""
guard_agent.py — MobilityLab GCS 에서 ACACT Guard 를 켜고 끄고 명령하기 위한 작은 상주 프로그램
════════════════════════════════════════════════════════════════
가드 노트북(Ubuntu)에서 항상 켜 두면 (install_agent.sh 가 로그인 시 자동 실행 등록)
GCS 가 같은 PC 든 다른 PC(Windows) 든 이 에이전트를 찾아서:

  - 가드 시작 / 종료   : python3 -u guard.py --drones D1,D2   (stdin 을 에이전트가 쥐고 있음)
  - 가드 명령         : load / start / g / g! / h / r / auto on|off / s  → 가드 stdin 으로 그대로 전달
  - 미션 생성         : python3 -u plan_gen.py --profile .. --drones .. --from-vehicles --bearing ..
  - 화면 출력         : 가드·plan_gen 의 터미널 출력을 GCS 콘솔로 전달

가드의 판단·회피 로직과는 무관하다. GCS 가 꺼지거나 연결이 끊겨도 가드는 계속 돈다
(에이전트가 가드를 쥐고 있으므로). 에이전트를 끄면(Ctrl+C) 가드에 q 를 보내 정상 종료한다.

UDP 47003 (ACACT_AGENT_PORT). 명령은 허용된 주소에서만 받는다:
  127.0.0.1, ACACT_GCS 에 적힌 주소, ACACT_AGENT_ALLOW (쉼표 구분, 예: 192.168.1.20)
  --allow-lan 을 주면 사설망(10/8, 172.16/12, 192.168/16) 전체 허용 (시험용)

  python3 guard_agent.py                  # 같은 PC 의 GCS 만
  python3 guard_agent.py --allow-lan      # 같은 망의 Windows GCS 도
"""
import argparse
import ipaddress
import json
import os
import select
import signal
import socket
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

PORT = int(os.environ.get("ACACT_AGENT_PORT", "47003"))
GCS_STATUS_PORT = 47001
SCRIPTS = {"guard": "guard.py", "plan": "plan_gen.py", "params": "set_params.py"}
DRONE_IDS = ("D1", "D2", "D3", "D4")


def python_bin():
    venv = os.path.expanduser("~/acact-venv/bin/python")
    return venv if os.path.exists(venv) else sys.executable


def _ask_python(code, fallback):
    """가드와 같은 파이썬(venv)으로 config/scenarios 를 읽는다 (numpy 등 의존성 때문에)"""
    try:
        env = dict(os.environ, ACACT_DRONES="")
        out = subprocess.run([python_bin(), "-c", code], cwd=HERE, env=env, capture_output=True, timeout=20, text=True)
        return json.loads(out.stdout.strip().splitlines()[-1])
    except Exception:
        return fallback


def list_scenarios():
    return _ask_python("import json, scenarios as S; print(json.dumps([{'name': k, 'title': v[0]} for k, v in S.SCENARIOS.items()], ensure_ascii=False))", [])


def list_profiles():
    return _ask_python("import json, config as C; print(json.dumps(list(C.HOME_LAYOUTS)))", ["oregon", "oregon2", "hwaseong"])


def _child_setup():
    # 에이전트가 죽으면 자식(가드)도 SIGINT 를 받아 정상 종료 절차(회피 중 기체 HOLD)를 밟는다
    try:
        import ctypes
        ctypes.CDLL("libc.so.6").prctl(1, signal.SIGINT)    # PR_SET_PDEATHSIG
    except Exception:
        pass
    os.setsid()


def clean_drones(v):
    ids = [x.strip().upper() for x in str(v or "").split(",") if x.strip()]
    ids = [x for x in ids if x in DRONE_IDS]
    return ",".join(dict.fromkeys(ids))


class Agent:
    def __init__(self, a):
        self.a = a
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(("0.0.0.0", PORT))
        self.allow = {"127.0.0.1"}
        for part in (os.environ.get("ACACT_GCS", "") + "," + os.environ.get("ACACT_AGENT_ALLOW", "")).split(","):
            host = part.strip().rpartition(":")[0] or part.strip()
            if host:
                self.allow.add(host)
        self.gcs = set()              # GCS addresses that said hello (host, port)
        self.proc = None              # running child (guard or plan_gen)
        self.kind = ""                # "guard" | "plan" | "params"
        self.args = []
        self.started = 0.0
        self.exit_code = None
        self.lines = []               # [(n, text)]
        self.n = 0
        self.buf = b""
        self.scen = list_scenarios()
        self.profiles = list_profiles()
        self.last_status = 0.0
        self.dirty = True

    # ── 허용 주소 ──
    def allowed(self, host):
        if host in self.allow:
            return True
        if self.a.allow_lan:
            try:
                return ipaddress.ip_address(host).is_private
            except ValueError:
                return False
        return False

    def out(self, text):
        self.n += 1
        self.lines = (self.lines + [(self.n, text.rstrip("\r"))])[-400:]
        print(text, flush=True)
        self.dirty = True

    # ── 자식 프로세스 ──
    def spawn(self, kind, args, gcs_host):
        if self.proc and self.proc.poll() is None:
            self.out(f"[agent] 이미 {self.kind} 실행 중 — 먼저 종료하세요")
            return
        env = dict(os.environ)
        if args.get("drones"):
            env["ACACT_DRONES"] = args["drones"]
        if args.get("profile"):
            env["ACACT_PROFILE"] = args["profile"]
        if kind == "guard" and gcs_host:
            # 가드 상태(gcs_link.py)가 이 GCS 로 가도록
            targets = {f"{gcs_host}:{GCS_STATUS_PORT}"} | {f"{h}:{GCS_STATUS_PORT}" for h, _ in self.gcs}
            env["ACACT_GCS"] = ",".join(sorted(targets))
        cmd = [python_bin(), "-u", SCRIPTS[kind]]
        if args.get("drones"):
            cmd += ["--drones", args["drones"]]
        if kind == "plan":
            if args.get("profile"):
                cmd += ["--profile", args["profile"]]
            cmd += ["--from-vehicles", "--bearing", f"{float(args.get('bearing', 0.0)):.1f}"]
        if kind == "params" and args.get("apply"):
            cmd += ["--apply"]
        self.out(f"[agent] 실행: {' '.join(cmd[1:])}")
        self.proc = subprocess.Popen(cmd, cwd=HERE, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT, bufsize=0, preexec_fn=_child_setup)
        os.set_blocking(self.proc.stdout.fileno(), False)
        self.kind, self.args, self.started, self.exit_code = kind, cmd[2:], time.time(), None
        self.dirty = True

    def write(self, line):
        if not (self.proc and self.proc.poll() is None and self.kind == "guard"):
            self.out(f"[agent] 가드가 실행 중이 아님 — '{line}' 무시")
            return
        try:
            self.proc.stdin.write((line + "\n").encode())
            self.proc.stdin.flush()
            self.out(f"> {line}")
        except OSError as e:
            self.out(f"[agent] 명령 전달 실패: {e}")

    def stop(self, force=False):
        if not (self.proc and self.proc.poll() is None):
            return
        if self.kind == "guard" and not force:
            self.write("q")       # 가드가 회피 중 기체 HOLD 후 요약 기록하고 종료
            return
        self.out(f"[agent] {self.kind} 강제 종료")
        self.proc.send_signal(signal.SIGINT)

    def pump_child(self):
        if not self.proc:
            return
        try:
            chunk = self.proc.stdout.read()
        except (BlockingIOError, OSError):
            chunk = None
        if chunk:
            self.buf += chunk
            *done, self.buf = self.buf.split(b"\n")
            for ln in done:
                self.out(ln.decode("utf-8", "replace"))
        if self.proc.poll() is not None and self.exit_code is None:
            if self.buf:
                self.out(self.buf.decode("utf-8", "replace"))
                self.buf = b""
            self.exit_code = self.proc.returncode
            self.out(f"[agent] {self.kind} 종료 (코드 {self.exit_code})")
            self.dirty = True

    # ── GCS 통신 ──
    def status(self):
        running = bool(self.proc and self.proc.poll() is None)
        return {"src": "acact_agent", "proto": 1, "host": socket.gethostname(), "dir": HERE,
                "state": (self.kind if running else "idle"), "args": self.args if running else [],
                "uptime": round(time.time() - self.started, 1) if running else 0,
                "exit": self.exit_code, "scenarios": self.scen, "profiles": self.profiles,
                "lines": [{"n": n, "text": t} for n, t in self.lines[-60:]]}

    def send_status(self):
        data = json.dumps(self.status(), ensure_ascii=False).encode()
        for addr in list(self.gcs):
            try:
                self.sock.sendto(data, addr)
            except OSError:
                self.gcs.discard(addr)
        self.last_status = time.time()
        self.dirty = False

    def handle(self, data, addr):
        host = addr[0]
        if not self.allowed(host):
            return
        try:
            m = json.loads(data.decode())
        except ValueError:
            return
        op = m.get("op", "")
        if addr not in self.gcs:
            self.gcs.add(addr)
            self.out(f"[agent] GCS 연결: {host}")
        if op == "hello":
            self.dirty = True
        elif op == "start":
            self.spawn("guard", {"drones": clean_drones(m.get("drones")), "profile": m.get("profile") if m.get("profile") in self.profiles else ""}, host)
        elif op == "plan":
            self.spawn("plan", {"drones": clean_drones(m.get("drones")), "profile": m.get("profile") if m.get("profile") in self.profiles else "",
                                "bearing": m.get("bearing", 0.0)}, host)
        elif op == "params":
            self.spawn("params", {"drones": clean_drones(m.get("drones")), "apply": bool(m.get("apply"))}, host)
        elif op == "line":
            line = " ".join(str(m.get("line", "")).split())[:120]
            if line:
                self.write(line)
        elif op == "stop":
            self.stop(force=bool(m.get("force")))
        elif op == "bye":
            self.gcs.discard(addr)

    def run(self):
        self.out(f"[agent] ACACT Guard 에이전트 — UDP {PORT}, 폴더 {HERE}")
        self.out(f"[agent] 허용: {', '.join(sorted(self.allow))}{' + 사설망' if self.a.allow_lan else ''}")
        try:
            while True:
                r, _, _ = select.select([self.sock], [], [], 0.1)
                if r:
                    data, addr = self.sock.recvfrom(8192)
                    self.handle(data, addr)
                self.pump_child()
                if self.dirty and time.time() - self.last_status > 0.2 or time.time() - self.last_status > 1.0:
                    self.send_status()
        except KeyboardInterrupt:
            if self.proc and self.proc.poll() is None and self.kind == "guard":
                self.write("q")
                try:
                    self.proc.wait(15)
                except subprocess.TimeoutExpired:
                    self.proc.terminate()


def main():
    ap = argparse.ArgumentParser(description="ACACT Guard 에이전트 (MobilityLab GCS 연동)")
    ap.add_argument("--allow-lan", action="store_true", help="사설망의 GCS 명령 허용 (시험용)")
    Agent(ap.parse_args()).run()


if __name__ == "__main__":
    main()
