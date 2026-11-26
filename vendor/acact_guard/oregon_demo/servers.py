"""
servers.py — mavsdk_server 4개를 '자식 프로세스'로 띄운다.
════════════════════════════════════════════════════════════════
왜 필요한가:
  MAVSDK 는 offboard setpoint 를 mavsdk_server 안에서 20 Hz 로 계속 재송신한다.
  mavsdk_server 를 따로 띄워 두면, 가드(파이썬)가 죽어도 서버가 마지막 회피 속도를
  계속 보내서 PX4 가 offboard 상실을 감지하지 못하고 그 속도로 계속 날아간다.
  → 서버를 가드의 자식으로 띄우고, 가드가 죽으면 커널이 서버도 같이 죽이도록(PDEATHSIG) 한다.
     서버가 죽으면 setpoint 가 끊기고 PX4 가 COM_OF_LOSS_T 후 Hold 로 전환한다.
"""
import ctypes
import os
import shutil
import signal
import subprocess
import time

import config as C


def _server_bin():
    try:
        import mavsdk
        p = os.path.join(os.path.dirname(mavsdk.__file__), "bin", "mavsdk_server")
        if os.path.exists(p):
            return p
    except Exception:
        pass
    p = shutil.which("mavsdk_server")
    if p:
        return p
    raise FileNotFoundError("mavsdk_server 를 찾을 수 없음 — pip install \"mavsdk<4\" 확인")


def _die_with_parent():
    # Linux: 부모가 죽으면 SIGKILL 을 받도록
    try:
        libc = ctypes.CDLL("libc.so.6")
        PR_SET_PDEATHSIG = 1
        libc.prctl(PR_SET_PDEATHSIG, signal.SIGKILL)
    except Exception:
        pass


class Servers:
    def __init__(self, quiet=True):
        self.procs = []
        self.quiet = quiet

    def start(self):
        exe = _server_bin()
        for d in C.DRONES:
            args = [exe, "-p", str(d["port"]), f"udp://:{d['udp']}"]
            out = subprocess.DEVNULL if self.quiet else None
            p = subprocess.Popen(args, stdout=out, stderr=out, preexec_fn=_die_with_parent)
            self.procs.append(p)
        time.sleep(1.0)
        dead = [C.DRONES[i]["id"] for i, p in enumerate(self.procs) if p.poll() is not None]
        if dead:
            self.stop()
            raise RuntimeError(f"mavsdk_server 시작 실패: {dead} — 같은 포트를 쓰는 mavsdk_server 가 이미 떠 있는지 확인 "
                               f"(pkill mavsdk_server)")
        return self

    def kill_now(self):
        """워치독용: 즉시 강제 종료 (setpoint 스트림 차단)"""
        for p in self.procs:
            try:
                os.kill(p.pid, signal.SIGKILL)
            except Exception:
                pass

    def stop(self):
        for p in self.procs:
            try:
                p.terminate()
            except Exception:
                pass
        for p in self.procs:
            try:
                p.wait(timeout=2)
            except Exception:
                try:
                    p.kill()
                except Exception:
                    pass
        self.procs = []
