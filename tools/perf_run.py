#!/usr/bin/env python3
"""Performance and soak measurements of one MobilityLab GCS AppImage (tools/perf.yml).

Run both versions in the same job on the same runner so the numbers are comparable.
All numbers come from this run; nothing is estimated. Environment: GitHub-hosted ubuntu-24.04
runner (4 vCPU, 16 GB), Xvfb 1920x1080, Mesa llvmpipe software OpenGL (no GPU: GPU load and
GPU frame rate are NOT measured — the FPS here is software rendering and only comparable
between the two versions on the same runner).

Phases
  startup   3 launches, seconds until the main window is mapped (xdotool) and, when the build
            logs it (v1.2+), until the console reports ready (MLPERF ready)
  idle      90 s with no vehicle: CPU % of the whole process tree, RSS
  demo      the built-in 3-vehicle demo with ACACT auto run (MLGCS_DEMO=trio, MLGCS_DEMO_AUTO=1):
            CPU %, RSS; v1.2+ also logs frame rate, mode-switch times and ACACT tick time
  soak      (optional) the demo repeated for --soak seconds: RSS / CPU every 30 s
"""
import argparse, json, os, re, signal, subprocess, sys, time

HZ = os.sysconf("SC_CLK_TCK")
PAGE = os.sysconf("SC_PAGE_SIZE")


def tree(pid):
    out, todo = set(), [pid]
    while todo:
        p = todo.pop()
        out.add(p)
        try:
            for c in open(f"/proc/{p}/task/{p}/children").read().split():
                todo.append(int(c))
        except OSError:
            pass
    return out


def sample(pid):
    cpu, rss = 0, 0
    for p in tree(pid):
        try:
            st = open(f"/proc/{p}/stat").read().rsplit(")", 1)[1].split()
            cpu += int(st[11]) + int(st[12])
            rss += int(open(f"/proc/{p}/statm").read().split()[1]) * PAGE
        except OSError:
            pass
    return cpu, rss


def launch(app, env_extra, log):
    env = dict(os.environ, DISPLAY=":71", QT_QPA_PLATFORM="xcb", LIBGL_ALWAYS_SOFTWARE="1", **env_extra)
    return subprocess.Popen([app], stdout=open(log, "w"), stderr=subprocess.STDOUT, env=env, start_new_session=True)


def stop(p):
    try:
        os.killpg(p.pid, signal.SIGINT)
        p.wait(20)
    except Exception:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except Exception:
            pass
    time.sleep(2)


def wait_window(t0, timeout=90):
    while time.time() - t0 < timeout:
        r = subprocess.run(["xdotool", "search", "--onlyvisible", "--name", "^MobilityLabGCS$"], capture_output=True, text=True)
        if r.stdout.strip():
            return time.time() - t0
        time.sleep(0.1)
    return None


def wait_log(log, pat, t0, timeout):
    while time.time() - t0 < timeout:
        try:
            if re.search(pat, open(log, errors="ignore").read()):
                return time.time() - t0
        except OSError:
            pass
        time.sleep(0.2)
    return None


def measure(pid, seconds, every=2.0):
    rows = []
    c0, _ = sample(pid)
    t0 = time.time()
    tp, cp = t0, c0
    while time.time() - t0 < seconds:
        time.sleep(every)
        c, r = sample(pid)
        t = time.time()
        rows.append({"t": round(t - t0, 1), "cpu_pct": round(100.0 * (c - cp) / HZ / (t - tp), 1), "rss_mb": round(r / 2**20, 1)})
        tp, cp = t, c
    return rows


def stats(rows, key):
    v = [r[key] for r in rows]
    if not v:
        return None
    v2 = sorted(v)
    return {"mean": round(sum(v) / len(v), 1), "p95": v2[int(0.95 * (len(v2) - 1))], "max": max(v), "first": v[0], "last": v[-1]}


def perf_lines(log):
    """v1.2+ ML_PERF=1 lines: MLPERF fps N · MLPERF mode X ms · MLPERF acact tick_ms mean max · MLPERF ready ms"""
    try:
        txt = open(log, errors="ignore").read()
    except OSError:
        return {}
    fps = [float(x) for x in re.findall(r"MLPERF fps ([\d.]+)", txt)]
    modes = [float(x) for x in re.findall(r"MLPERF mode \w+ ([\d.]+) ms", txt)]
    tick = re.findall(r"MLPERF acact tick_ms mean ([\d.]+) max ([\d.]+)", txt)
    link = re.findall(r"MLPERF link rx_lag_ms mean ([\d.]+) max ([\d.]+)", txt)
    out = {}
    if fps:
        out["fps"] = {"mean": round(sum(fps) / len(fps), 1), "min": min(fps), "samples": len(fps)}
    if modes:
        out["mode_switch_ms"] = {"mean": round(sum(modes) / len(modes), 1), "max": max(modes), "samples": len(modes)}
    if tick:
        m = [float(a) for a, _ in tick]; mx = [float(b) for _, b in tick]
        out["acact_tick_ms"] = {"mean": round(sum(m) / len(m), 3), "max": max(mx), "samples": len(m)}
    if link:
        m = [float(a) for a, _ in link]; mx = [float(b) for _, b in link]
        out["link_rx_lag_ms"] = {"mean": round(sum(m) / len(m), 2), "max": max(mx), "samples": len(m)}
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--app", required=True)
    ap.add_argument("--label", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--soak", type=int, default=0)
    ap.add_argument("--demo", type=int, default=240)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    res = {"label": a.label, "env": "GitHub ubuntu-24.04 runner, Xvfb 1920x1080, Mesa llvmpipe (no GPU)", "phases": {}}
    base_env = {"ML_PERF": "1", "MLGCS_NO_ONBOARDING": "1"}

    # startup ×3 (the first is a cold start of the AppImage: squashfs mount + first QML compile)
    st = []
    for i in range(3):
        log = f"{a.out}/{a.label}-startup{i}.log"
        t0 = time.time()
        p = launch(a.app, base_env, log)
        w = wait_window(t0)
        r = wait_log(log, r"MLPERF ready", t0, 60)
        st.append({"window_s": None if w is None else round(w, 2), "ready_s": None if r is None else round(r, 2)})
        time.sleep(3)
        stop(p)
    res["phases"]["startup"] = st

    # idle
    log = f"{a.out}/{a.label}-idle.log"
    p = launch(a.app, base_env, log)
    wait_window(time.time())
    time.sleep(15)
    rows = measure(p.pid, 90)
    stop(p)
    res["phases"]["idle"] = {"seconds": 90, "cpu_pct": stats(rows, "cpu_pct"), "rss_mb": stats(rows, "rss_mb"), "perf": perf_lines(log)}

    # demo, 3 vehicles + ACACT auto run
    log = f"{a.out}/{a.label}-demo.log"
    p = launch(a.app, dict(base_env, MLGCS_DEMO="trio", MLGCS_DEMO_AUTO="1", ML_PERF_MODES="1"), log)
    wait_window(time.time())
    act = wait_log(log, r"MLDEMO active true", time.time(), 60)
    rows = measure(p.pid, a.demo)
    stop(p)
    res["phases"]["demo"] = {"seconds": a.demo, "demo_started": act is not None, "cpu_pct": stats(rows, "cpu_pct"), "rss_mb": stats(rows, "rss_mb"), "perf": perf_lines(log),
                             "acact_interventions": len(re.findall(r"회피 개입", open(log, errors="ignore").read()))}
    json.dump(rows, open(f"{a.out}/{a.label}-demo-samples.json", "w"))

    # soak: the demo repeated
    if a.soak > 0:
        log = f"{a.out}/{a.label}-soak.log"
        p = launch(a.app, dict(base_env, MLGCS_DEMO="trio", MLGCS_DEMO_AUTO="1", MLGCS_DEMO_REPEAT="1"), log)
        wait_window(time.time())
        t0 = time.time()
        rows = measure(p.pid, a.soak, every=30)
        alive = p.poll() is None
        stop(p)
        txt = open(log, errors="ignore").read()
        res["phases"]["soak"] = {"seconds_planned": a.soak, "seconds_run": round(time.time() - t0), "alive_at_end": alive,
                                 "cpu_pct": stats(rows, "cpu_pct"), "rss_mb": stats(rows, "rss_mb"),
                                 "demo_runs": len(re.findall(r"MLDEMO run \d+", txt)), "acact_interventions": len(re.findall(r"회피 개입", txt)),
                                 "perf": perf_lines(log)}
        json.dump(rows, open(f"{a.out}/{a.label}-soak-samples.json", "w"))

    json.dump(res, open(f"{a.out}/{a.label}.json", "w"), ensure_ascii=False, indent=1)
    print(json.dumps(res, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
