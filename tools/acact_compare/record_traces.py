#!/usr/bin/env python3
"""
record_traces.py — record ACACT Guard reference traces from the ORIGINAL Python code.

Runs the original sim_check.py (vendor/acact_guard_original, unmodified) and
records, at every guard step, the exact inputs given to core.GuardCore.step()
and the commands it returned. compare.cpp replays the inputs through the C++
port (custom/src/acact/AcactCore.cpp) and checks every command.

  python3 record_traces.py <out_dir> [--quick]

One trace file per run: <scenario>_<mode>_<drones>_s<seed>[_fault].trace
Line format (floats in repr = exact round trip):
  P <n_drones>                          header: number of guarded vehicles (Params)
  S <t> <count>                         step
  D id prio fresh age f r u vf vr vu rel_alt in_air mode g? gf gr rtl_alt goal_hold ga? ga h? hf hr
  C <type> <id> <vf> <vr> <vu>          takeover / vel / release
  E <id> <text>                         event
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ORIG = os.path.normpath(os.path.join(HERE, "..", "..", "vendor", "acact_guard_original"))

RUNNER = r'''
import sys, os
sys.path.insert(0, ORIG)
os.chdir(ORIG)
import core
import sim_check as S
out_path, name, mode, seed, fault = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5]
f = open(out_path, "w")
import config as C
f.write("P %d\n" % len(C.DRONES))
_orig_step = core.GuardCore.step
def r(x): return repr(float(x))
def step(self, t, drones):
    f.write("S %s %d\n" % (r(t), len(drones)))
    for d in drones:
        g = d.goal; ga = d.goal_alt; h = d.home
        f.write("D %s %d %d %s %s %s %s %s %s %s %s %d %s %d %s %s %s %d %d %s %d %s %s\n" % (
            d.id, d.prio, int(bool(d.fresh)), r(d.age), r(d.f), r(d.r), r(d.u), r(d.vf), r(d.vr), r(d.vu),
            r(d.rel_alt), int(bool(d.in_air)), d.mode,
            int(g is not None), r(g[0] if g else 0), r(g[1] if g else 0), r(d.rtl_alt), int(bool(d.goal_hold)),
            int(ga is not None), r(ga if ga is not None else 0),
            int(h is not None), r(h[0] if h else 0), r(h[1] if h else 0)))
    cmds = _orig_step(self, t, drones)
    for kind, did, val in cmds:
        if kind == "event":
            f.write("E %s %s\n" % (did, str(val).replace("\n", " ")))
        elif val is None:
            f.write("C %s %s 0.0 0.0 0.0\n" % (kind, did))
        else:
            f.write("C %s %s %s %s %s\n" % (kind, did, r(val[0]), r(val[1]), r(val[2])))
    return cmds
core.GuardCore.step = step
S.GuardCore = core.GuardCore
fl = None
if fault != "-":
    fid, ft = fault.split(":")
    fl = (fid, float(ft))
res = S.run(name, mode, seed=seed, fault=fl, plot=False)
f.close()
print("%s %s s%d %s min3d=%.2f takeovers=%d landed=%s" % (name, mode, seed, fault, res["min3d"], res["takeovers"], res["all_landed"]))
'''.replace("ORIG", repr(ORIG))


def runs(quick):
    four = ["S0_integrated", "S1_formation", "S2_headon", "S3_cross4", "S4_merge", "S5_survey", "S6_linkloss"]
    seeds = [1, 2] if quick else [1, 2, 3]
    out = []
    for n in four:
        for s in seeds:
            out.append(("D1,D2,D3,D4", n, "demo", s, "-"))
    out.append(("D1,D2,D3,D4", "S3_cross4", "rehearsal", 1, "-"))
    out += [("D1,D2,D3,D4", "S3_cross4", "demo", 1, "D1:5"), ("D1,D2,D3,D4", "S2_headon", "demo", 1, "D1:6"),
            ("D1,D2,D3,D4", "S6_linkloss", "demo", 1, "D2:1")]
    for s in seeds:
        out.append(("D1,D2", "S7_duo", "demo", s, "-"))
        out.append(("D1,D3", "S2_headon", "demo", s, "-"))
    out.append(("D1,D2", "S7_duo", "demo", 1, "D2:4"))
    return out


def main():
    out_dir = sys.argv[1]
    quick = "--quick" in sys.argv
    os.makedirs(out_dir, exist_ok=True)
    runner = os.path.join(out_dir, "_runner.py")
    with open(runner, "w") as fh:
        fh.write(RUNNER)
    ok = True
    for drones, n, mode, seed, fault in runs(quick):
        tag = f"{n}_{mode}_{drones.replace(',', '')}_s{seed}" + ("" if fault == "-" else "_fault" + fault.replace(":", "-"))
        path = os.path.join(out_dir, tag + ".trace")
        env = dict(os.environ, ACACT_DRONES=drones, MPLBACKEND="Agg")
        p = subprocess.run([sys.executable, runner, path, n, mode, str(seed), fault], env=env, capture_output=True, text=True)
        if p.returncode != 0:
            ok = False
            print("FAILED", tag, p.stderr[-800:])
        else:
            print(p.stdout.strip())
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
