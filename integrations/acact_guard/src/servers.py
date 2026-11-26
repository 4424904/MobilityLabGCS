"""
servers.py — mavsdk_server 4개를 '자식 프로세스'로 띄운다.
════════════════════════════════════════════════════════════════
왜 필요한가:
  MAVSDK 는 offboard setpoint 를 mavsdk_server 안에서 20 Hz 로 계속 재송신한다.
  mavsdk_server 를 따로 띄워 두면, 가드(파이썬)가 죽어도 서버가 마지막 회피 속도를
  계속 보내서 PX4 가 offboard 상실을 감지하지 못하고 그 속도로 계속 날아간다.
  → 서버를 가드의 자식으로 띄우고, 가드가 죽으면 커널이 서버도 같이 죽이도록 한다.
     Linux: PDEATHSIG / Windows: Job Object (KILL_ON_JOB_CLOSE)
     서버가 죽으면 setpoint 가 끊기고 PX4 가 COM_OF_LOSS_T 후 Hold 로 전환한다.
"""
import ctypes
import os
import shutil
import signal
import subprocess
import sys
import time

WINDOWS = sys.platform.startswith("win")

import config as C


def _server_bin():
    try:
        import mavsdk
        for name in ("mavsdk_server.exe", "mavsdk_server") if WINDOWS else ("mavsdk_server",):
            p = os.path.join(os.path.dirname(mavsdk.__file__), "bin", name)
            if os.path.exists(p):
                return p
    except Exception:
        pass
    p = shutil.which("mavsdk_server")
    if p:
        return p
    raise FileNotFoundError("mavsdk_server 를 찾을 수 없음 — pip install \"mavsdk<4\" 확인")


class _WinJob:
    """Windows: 가드 프로세스가 죽으면(작업 핸들이 닫히면) 서버도 함께 종료되도록"""
    def __init__(self):
        from ctypes import wintypes
        k = ctypes.WinDLL("kernel32", use_last_error=True)
        self.k = k
        k.CreateJobObjectW.restype = wintypes.HANDLE
        k.OpenProcess.restype = wintypes.HANDLE
        self.h = k.CreateJobObjectW(None, None)

        class IO(ctypes.Structure):
            _fields_ = [(n, ctypes.c_ulonglong) for n in ("r", "w", "o", "rt", "wt", "ot")]

        class BASIC(ctypes.Structure):
            _fields_ = [("PerProcessUserTimeLimit", ctypes.c_int64), ("PerJobUserTimeLimit", ctypes.c_int64),
                        ("LimitFlags", wintypes.DWORD), ("MinimumWorkingSetSize", ctypes.c_size_t),
                        ("MaximumWorkingSetSize", ctypes.c_size_t), ("ActiveProcessLimit", wintypes.DWORD),
                        ("Affinity", ctypes.c_size_t), ("PriorityClass", wintypes.DWORD),
                        ("SchedulingClass", wintypes.DWORD)]

        class EXT(ctypes.Structure):
            _fields_ = [("Basic", BASIC), ("Io", IO), ("ProcessMemoryLimit", ctypes.c_size_t),
                        ("JobMemoryLimit", ctypes.c_size_t), ("PeakProcessMemoryUsed", ctypes.c_size_t),
                        ("PeakJobMemoryUsed", ctypes.c_size_t)]

        info = EXT()
        info.Basic.LimitFlags = 0x2000          # JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        k.SetInformationJobObject(self.h, 9, ctypes.byref(info), ctypes.sizeof(info))   # ExtendedLimitInformation

    def add(self, pid):
        hp = self.k.OpenProcess(0x0001 | 0x0100, False, pid)     # PROCESS_TERMINATE | PROCESS_SET_QUOTA
        if hp:
            self.k.AssignProcessToJobObject(self.h, hp)
            self.k.CloseHandle(hp)


_JOB = None


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
        global _JOB
        exe = _server_bin()
        for d in C.DRONES:
            args = [exe, "-p", str(d["port"]), f"udp://:{d['udp']}"]
            out = subprocess.DEVNULL if self.quiet else None
            if WINDOWS:
                p = subprocess.Popen(args, stdout=out, stderr=out, creationflags=0x08000000)   # CREATE_NO_WINDOW
                try:
                    _JOB = _JOB or _WinJob()
                    _JOB.add(p.pid)
                except Exception as e:
                    print(f"※ 서버 작업 묶기 실패 ({e}) — 가드가 비정상 종료되면 mavsdk_server 를 직접 끄세요")
            else:
                p = subprocess.Popen(args, stdout=out, stderr=out, preexec_fn=_die_with_parent)
            self.procs.append(p)
        time.sleep(1.0)
        dead = [C.DRONES[i]["id"] for i, p in enumerate(self.procs) if p.poll() is not None]
        if dead:
            self.stop()
            raise RuntimeError(f"mavsdk_server 시작 실패: {dead} — 같은 포트를 쓰는 mavsdk_server 가 이미 떠 있는지 확인 "
                               f"({'작업 관리자에서 mavsdk_server.exe 종료' if WINDOWS else 'pkill mavsdk_server'})")
        return self

    def kill_now(self):
        """워치독용: 즉시 강제 종료 (setpoint 스트림 차단)"""
        for p in self.procs:
            try:
                p.kill() if WINDOWS else os.kill(p.pid, signal.SIGKILL)
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
