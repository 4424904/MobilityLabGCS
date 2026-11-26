# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

ACACT Guard: a laptop-side collision guard for 2–4 PX4 X500 drones flying QGC waypoint missions (Oregon demo; rehearsed at the Hwaseong test center). The guard watches all vehicles and, when a conflict is predicted, takes **only that vehicle** into Offboard, flies an ACACT avoidance velocity (Min & Nam, IEEE Access 2023), then hands it back to its mission. README.md (Korean) is the operator manual and holds the safety rules, field procedures, and validated simulation numbers.

## Commands

No build step, linter, or unit-test suite. Python 3 on Ubuntu, venv at `~/acact-venv` (created by `install.sh`). **`mavsdk` must be `<4`** (3.x gRPC API; 4.x breaks everything).

Verification is done with the offline simulator, which runs the real `core.GuardCore` against point-mass drones (no PX4 needed, a few seconds per run):

```bash
python3 sim_check.py --faults                              # all scenarios + link-loss fault injection
python3 sim_check.py S3_cross4 -v                          # one scenario, print event log
python3 sim_check.py S3_cross4 --mode rehearsal --seeds 8
python3 sim_check.py --profile hwaseong --drones D1,D3     # site profile / drone subset
python3 stress_check.py S7_duo 20 --profile oregon2 --drones D1,D2   # 8 degraded conditions × N seeds
```
Trajectory PNGs go to `sim_out/`. **After changing any value in `config.py` or logic in `core.py`, re-run `sim_check.py` (and `stress_check.py` for S7_duo) and compare min-separation against the tables in README.md** — the abort criterion in the field is < 5 m.

SITL / field flow:
```bash
./launch_sitl.sh                                  # PX4 SITL ×4
LINK=sitl ./demo.sh setup                         # routers → set_params → plan_gen (default SITE=oregon2 DRONES=D1,D2)
LINK=sitl ./demo.sh fly                           # guard_map.py + guard.py; then in guard: load S7_duo rehearsal → start
./demo.sh stop
```
Individually: `set_params.py --apply`, `plan_gen.py --profile <p> --drones <ids> --from-vehicles --bearing <deg|auto>`, `guard_map.py [--full]`, `guard.py --drones <ids>`. `LINK` = `wifi` (default, `router/wifi*.conf`), `radio` (`router/radio*.conf`), or `sitl`.

## Architecture

**Coordinate frame.** Everything in planning and decision logic uses the demo frame (F = forward from GCS toward demo area, R = right, U = up), origin at the demo center. `geo.Frame` converts lat/lon ↔ F/R using `center_lat/lon` and `bearing_deg` from `plans/site.json`, which `plan_gen.py` writes and `guard.py` reads.

**Pipeline:**
1. `scenarios.py` — `build(name, mode)` returns `{drone_id: [items]}` (takeoff / speed / wp / sync / land in F/R/alt). Each mission = common prefix (slow takeoff → STEP_FWD → transit to start → SYNC) + scenario segment + common suffix (climb to own layer → home → land). `mode="demo"` flies the scenario at `DEMO_ALT` (avoidance actually happens); `mode="rehearsal"` flies it at each drone's layer altitude (vertically separated, zero takeovers expected). SYNC points are `LOITER_UNLIM`, released by the guard's `g`/auto-advance.
2. `plan_gen.py` — converts those items to per-drone QGC `.plan` files under `plans/<mode>/<scenario>/<Dn>.plan` plus `plans/site.json`; `--from-vehicles` reads live positions/headings to anchor the frame.
3. `guard.py` — asyncio + MAVSDK runtime. Spawns one `mavsdk_server` per drone as child processes (`servers.py`, PDEATHSIG) so that if the guard dies the setpoint stream dies too; a watchdog thread kills the servers if the main loop stalls > 1 s. Each tick builds `DroneIn` snapshots, calls `GuardCore.step()`, and executes the returned commands via MAVSDK. Also handles operator commands (`load`, `start`, `g`, `g!`, `h`, `r`, `s`, `auto on|off`, `q`), preflight checks, auto-sync, CSV logs/summary in `logs/`, and UDP state to `guard_map.py` (`MAP_UDP`).
4. `core.py` — **MAVSDK-free decision logic shared by `guard.py` and `sim_check.py`**. `GuardCore.step(t, drones)` returns a command list: `("takeover", id, v)`, `("vel", id, v)`, `("release", id, None)`, `("event", id, text)`. Pair evaluation uses CPA prediction over `T_LOOK`; ignores pairs that are vertically separated (`V_SEP`), on/near their pads (`PAD_ZONE`), or vertical-only; STALE (telemetry-lost) drones are extrapolated with enlarged radius and dropped after `STALE_DROP_T`. Never takes over drones in manual (RC override) mode, below `MIN_TAKEOVER_ALT`, or not in MISSION/owned-OFFBOARD.

Keep `core.py` free of MAVSDK/IO so the simulator keeps exercising the exact same code that flies.

**Config gotchas (`config.py`):**
- The active drone set is resolved **at import time** from `--drones` in `sys.argv` or `ACACT_DRONES`, so any script that imports `config` honors `--drones` even before argparse runs. `DRONES` is the active subset; `ALL_DRONES` is all four (home slots and layers are always assigned from the 4-drone layout).
- When exactly 2 drones are active, the `DUO` block at the bottom overrides `MAX_H_SPEED`, `D_SAFE`, `ACACT["rs"]`, `ACACT["k_cpa"]`. Check that block before reasoning about effective values.
- Site profile (`oregon`, `oregon2`, `hwaseong`) comes from `ACACT_PROFILE` or `--profile` (scripts assign `C.PROFILE` after parsing); it only changes home-pad layout (`HOME_LAYOUTS`), not the scenario flight area.
- Some values must match PX4 parameters set by `set_params.py` (e.g. `DL_LOSS_T` ↔ `COM_DL_LOSS_T`, `TAKEOFF_SPEED` ↔ `MPC_TKO_SPEED`, `GOAL_HANDOFF` < `NAV_ACC_RAD`). Change both sides together.

**Scenarios:** `S7_duo` is 2-drone only (Oregon main demo); `S0_integrated` is the single-sortie combined run for 2–4 drones; `S1`–`S6` are individual maneuvers. `scenarios.available()` gates them by drone count.

## Safety-relevant invariants (don't break)

- Never tell users to run `mavsdk_server` separately; the guard must own it (otherwise a dead guard leaves the last avoidance velocity streaming).
- Guard must not touch vehicles under manual RC control, and must HOLD any Offboard vehicle it doesn't own.
- `h` (hold all) must be processed immediately even while other commands are in progress.
- RTL/layer altitudes (20/26/32/38 m) provide vertical separation for transit, return, and failsafe; `RTL_CONE_ANG=0` is required for that.
- Never use MAVSDK `mission_raw.set_current_mission_item`. If PX4 passes the target item instantly (a `DO_*` item, or a waypoint already within `NAV_ACC_RAD`), it never reports that index, and mavsdk_server re-sends forever (a Python-side timeout doesn't stop it). Later sync commands then fight it and the drone bounces between mission items. `Guard.set_current` sends `MISSION_SET_CURRENT` via `mavlink_direct` to the HEARTBEAT sysid and checks progress itself. `scenarios._speed_before_sync` keeps speed items from directly following a sync hold.
- `sim_check.py` doesn't model the MAVLink mission protocol, so mission-sequencing bugs only show up in SITL.

## SITL testing notes

- PX4 SITL's `rcS` forces `MAV_SYS_ID = instance+1` at every boot. The guard preflight reads the parameter, so set it at runtime (`build/px4_sitl_default/bin/px4-param --instance N set MAV_SYS_ID N`). That only changes the parameter; heartbeats still use instance+1.
- SITL has no RC, so the preflight check fails and `NAV_RCL_ACT=2` would trigger a return to home. Send centered-stick `MANUAL_CONTROL` (target = instance+1, source sysid ≠ 255 so it doesn't clash with QGC) to the GCS port `18570+N` at 10 Hz.
- After a sortie the drones land facing a different direction, and the preflight heading check (> 30°) correctly blocks the next `start`. Respawn SITL and rerun `plan_gen.py --from-vehicles`.
- PX4 releases after v1.17 replaced `COM_RC_OVERRIDE`/`COM_RC_STICK_OV` with `MAN_OVERRIDE_SPD`. `set_params.py` targets ≤ v1.17.
