#!/usr/bin/env bash
# SITL checks against MobilityLab GCS.
#   usage: ci_sitl.sh <build-dir | MobilityLabGCS*.AppImage> <output-dir> <px4-build-dir or ""> [case]
#   case: targets (default: 목표 조정 commands on ArduPilot + PX4)
#         s7duo | preflight | user | gcskill | linkloss | operator | modes  (ACACT, two PX4 SIH, see acact_sitl.py)
# Writes sitl-*.json, screenshots and logs to <output-dir>.
set -uo pipefail

APP_IN="$1"
OUT="$(mkdir -p "$2" && cd "$2" && pwd)"
PX4_BUILD="${3:-}"
CASE="${4:-targets}"
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"

if [[ -f "$APP_IN" && "$APP_IN" == *.AppImage ]]; then
    chmod +x "$APP_IN"
    (cd "$WORK" && "$APP_IN" --appimage-extract > /dev/null)
    BIN="$WORK/squashfs-root/AppRun"
    KILLPAT="$WORK/squashfs-root"
    echo "AppImage extracted: $BIN"
else
    BIN="$(find "$APP_IN" -maxdepth 3 -type f -name MobilityLabGCS -perm -u+x | head -n1)"
    KILLPAT="$BIN"
fi
[[ -z "$BIN" || ! -x "$BIN" ]] && { echo "::error::MobilityLabGCS not found in $APP_IN"; exit 1; }

# the GCS asks for serial-port permission otherwise (run through "sg dialout")
sudo usermod -a -G dialout "$USER" || true
python3 -m pip install --quiet pymavlink pillow || python3 -m pip install --quiet --break-system-packages pymavlink pillow

shot () { python3 -c "from PIL import ImageGrab; ImageGrab.grab(xdisplay='$1').save('$2')" || echo "screenshot failed: $2"; }

seed_settings () {
    rm -rf "$HOME/.config/MobilityLab"
    mkdir -p "$HOME/.config/MobilityLab"
    for f in MobilityLabGCS.ini MobilityLabGCS.conf; do
        printf '[FlightMap]\nmapProvider=Esri\nmapType=World Satellite\n' > "$HOME/.config/MobilityLab/$f"
    done
}

# ---- ArduCopter SITL binary -------------------------------------------------
get_arducopter () {
    local d="$WORK/ardupilot"
    mkdir -p "$d"
    for ch in stable latest; do
        if curl -fsSL -o "$d/arducopter" "https://firmware.ardupilot.org/Copter/$ch/SITL_x86_64_linux_gnu/arducopter"; then
            chmod +x "$d/arducopter"
            echo "ArduCopter SITL ($ch) downloaded" >&2
            break
        fi
    done
    curl -fsSL -o "$d/copter.parm" https://raw.githubusercontent.com/ArduPilot/ardupilot/master/Tools/autotest/default_params/copter.parm || true
    printf 'SERIAL1_PROTOCOL 2\nSERIAL1_BAUD 57\nSYSID_THISMAV 1\n' > "$d/extra.parm"
    [[ -x "$d/arducopter" ]] && echo "$d"
}

# ---- one run ------------------------------------------------------------------
# run_fw <fw> <command that starts the SITL, run in its own dir> <dir> <verifier link>
run_fw () {
    local fw="$1" start_cmd="$2" dir="$3" link="$4" extra_env="${5:-}"
    local disp=":$((80 + RANDOM % 9))"
    echo "=================== $fw on $disp"

    Xvfb "$disp" -screen 0 1920x1080x24 -nolisten tcp &
    local xvfb=$!
    sleep 2

    seed_settings
    sg dialout -c "$extra_env DISPLAY='$disp' QT_QPA_PLATFORM=xcb LIBGL_ALWAYS_SOFTWARE=1 ML_TEST_SETPOINTS=1 nice -n 10 '$BIN' > '$OUT/sitl-$fw-app.log' 2>&1" &
    sleep 10
    DISPLAY="$disp" xdotool search --onlyvisible --name ".*" 2>/dev/null | while read -r w; do
        DISPLAY="$disp" xdotool windowmove "$w" 0 0 windowsize "$w" 100% 100% || true
    done

    (cd "$dir" && eval "$start_cmd") > "$OUT/sitl-$fw-sim.log" 2>&1 &
    local sim=$!

    python3 "$HERE/sitl_check.py" --fw "$fw" --conn "$link" --out "$OUT" --timeout 450 > "$OUT/sitl-$fw-check.log" 2>&1 &
    local chk=$!

    local n=0
    while kill -0 "$chk" 2>/dev/null; do
        sleep 30
        n=$((n + 1))
        shot "$disp" "$OUT/sitl-$fw-$n.png"
        [[ $n -ge 15 ]] && break
    done
    wait "$chk"; local rc=$?
    shot "$disp" "$OUT/sitl-$fw-final.png"

    echo "--- $fw check log"
    tail -n 40 "$OUT/sitl-$fw-check.log"
    echo "--- $fw GCS test steps"
    grep -h "MLTEST" "$OUT/sitl-$fw-app.log" || echo "(no MLTEST lines)"

    kill "$sim" 2>/dev/null; pkill -f arducopter 2>/dev/null; pkill -f "bin/px4" 2>/dev/null
    pkill -f "$KILLPAT" 2>/dev/null; sleep 2; pkill -9 -f "$KILLPAT" 2>/dev/null
    kill "$xvfb" 2>/dev/null
    wait 2>/dev/null
    return $rc
}

status=0

# ---- ACACT cases: two PX4 SIH quadcopters (oregon layout, D2 15 m east of D1, facing north) ------
start_app () {   # start_app <case> <log>   (case "modes" = the "user" flight with ML_TEST_UI_MODES=1)
    local drv="$1" modes=0
    if [[ "$1" == "modes" ]]; then drv="user"; modes=1; fi
    sg dialout -c "ML_TEST_UI_MODES=$modes ML_TEST_ACACT=1 ML_TEST_ACACT_N=2 ML_TEST_ACACT_CASE='$drv' ML_TEST_PLAN_DIR='$OUT/plans' DISPLAY='$disp' QT_QPA_PLATFORM=xcb LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=1 nice -n 19 taskset -c $GCS_CPUS '$BIN' > '$2' 2>&1" &
    sleep 10
    DISPLAY="$disp" xdotool search --onlyvisible --name ".*" 2>/dev/null | while read -r w; do
        DISPLAY="$disp" xdotool windowmove "$w" 0 0 windowsize "$w" 100% 100% || true
    done
}
wait_log () {    # wait_log <file> <regex> <timeout s>
    local end=$((SECONDS + $3))
    while (( SECONDS < end )); do grep -qE "$2" "$1" 2>/dev/null && return 0; sleep 0.2; done
    return 1
}
kill_app () { pkill -9 -f "$KILLPAT" 2>/dev/null; sleep 1; }
link () {        # link cut|restore <instance>: PX4 instance i talks to the GCS from udp 18570+i
    local port=$((18570 + $2)) op="-I"
    [[ "$1" == restore ]] && op="-D"
    sudo iptables $op INPUT -i lo -p udp --sport "$port" -j DROP
    sudo iptables $op INPUT -i lo -p udp --dport "$port" -j DROP
}

# CPU split: the GCS (software-rendered map, llvmpipe limited to one thread) on the last core at low priority,
# the two PX4 SIH instances on all cores at high priority. A starved SIH misses sensor updates
# ("BARO #0 failed: TIMEOUT") and PX4 lands at once ("Failsafe: blind land") — a test-bench artefact.
# (Pinning each PX4 instance to one core made it worse: each instance runs many threads.)
NCPU=$(nproc)
GCS_CPUS="$((NCPU - 1))"
echo "CPUs: $NCPU (GCS on $GCS_CPUS, PX4 on all)"

run_acact () {
    local c="$1"
    disp=":$((90 + RANDOM % 9))"
    echo "=================== ACACT case $c (2 x PX4 SIH) on $disp"
    Xvfb "$disp" -screen 0 1920x1080x24 -nolisten tcp &
    local xvfb=$!
    sleep 2
    seed_settings
    rm -rf "$HOME/Documents/MobilityLab/ACACT"
    python3 "$HERE/acact_sitl.py" --make-plans "$OUT/plans"
    local applog="$OUT/sitl-acact-$c-app.log"
    start_app "$c" "$applog"
    # same vehicle parameters as the original set_params.py, except what SITL has no hardware for (RC)
    local common="PX4_SIM_MODEL=sihsim_quadx PX4_PARAM_COM_OF_LOSS_T=1.0 PX4_PARAM_COM_OBL_RC_ACT=5 PX4_PARAM_NAV_ACC_RAD=2.0 \
PX4_PARAM_MPC_TKO_SPEED=1.0 PX4_PARAM_MPC_XY_CRUISE=3.0 PX4_PARAM_MIS_TAKEOFF_ALT=8.0 PX4_PARAM_RTL_CONE_ANG=0 \
PX4_PARAM_COM_RC_IN_MODE=4 PX4_PARAM_NAV_RCL_ACT=0 PX4_PARAM_COM_RCL_EXCEPT=7 PX4_PARAM_NAV_DLL_ACT=0 PX4_PARAM_SIM_BAT_DRAIN=1800"
    rm -rf "$PX4_BUILD/rootfs0" "$PX4_BUILD/rootfs1"; mkdir -p "$PX4_BUILD/rootfs0" "$PX4_BUILD/rootfs1"
    (cd "$PX4_BUILD/rootfs0" && eval "$common PX4_PARAM_SIH_LOC_LAT0=37.2100856 PX4_PARAM_SIH_LOC_LON0=126.8307462 PX4_PARAM_RTL_RETURN_ALT=20 ../bin/px4 -i 0 -d ../etc") > "$OUT/sitl-acact-$c-px4-0.log" 2>&1 &
    local p0=$!
    (cd "$PX4_BUILD/rootfs1" && eval "$common PX4_PARAM_SIH_LOC_LAT0=37.2100856 PX4_PARAM_SIH_LOC_LON0=126.8309154 PX4_PARAM_RTL_RETURN_ALT=26 ../bin/px4 -i 1 -d ../etc") > "$OUT/sitl-acact-$c-px4-1.log" 2>&1 &
    local p1=$!
    # the runner is small: keep the simulators ahead of the GCS's software-rendered map so the PX4 estimators
    # do not starve (seen as "Failsafe: blind land" right after takeoff on a loaded runner)
    # every thread of both PX4 processes (renice works per thread on Linux); again once all modules are up
    px4_prio () { for pid in $(pgrep -f "bin/px4"); do for t in /proc/$pid/task/*; do sudo renice -n -10 -p "${t##*/}" > /dev/null 2>&1; done; done; }
    sleep 2; px4_prio
    ( sleep 15; px4_prio ) &
    python3 "$HERE/acact_sitl.py" --out "$OUT" --case "$c" --app-log "$applog" --timeout 1200 > "$OUT/sitl-acact-$c-check.log" 2>&1 &
    local chk=$!

    # fault injection
    case "$c" in
        gcskill)
            (
                if wait_log "$applog" "MLACACT D[0-9]+ \| 회피 개입" 900; then
                    sleep 1
                    kill_app
                    date +%s.%N > "$OUT/gcs_killed_at"
                    echo "GCS killed (kill -9) during avoidance"
                    sleep 15
                    shot "$disp" "$OUT/sitl-acact-$c-after-kill.png"
                    start_app restart "$OUT/sitl-acact-$c-app-restart.log"
                    date +%s.%N > "$OUT/gcs_restarted_at"
                    echo "GCS restarted"
                fi
            ) &
            ;;
        linkloss)
            (
                if wait_log "$applog" "MLACACT D[0-9]+ \| 회피 개입" 900; then
                    sleep 1
                    link cut 1
                    date +%s.%N > "$OUT/link_cut_at"
                    echo "D2 link cut"
                    sleep 12
                    link restore 1
                    date +%s.%N > "$OUT/link_restored_at"
                    echo "D2 link restored"
                fi
            ) &
            ;;
    esac

    local n=0
    while kill -0 "$chk" 2>/dev/null; do
        sleep 20
        n=$((n + 1))
        shot "$disp" "$OUT/sitl-acact-$c-$n.png"
        [[ $n -ge 75 ]] && break
    done
    wait "$chk"; local rc=$?
    shot "$disp" "$OUT/sitl-acact-$c-final.png"
    echo "--- ACACT $c check"; cat "$OUT/sitl-acact-$c-check.log"
    echo "--- GCS ACACT events"; grep -h "MLACACT" "$OUT"/sitl-acact-$c-app*.log | sed 's/ - qml.*//' | grep -v "preflight D[0-9] 배터리"
    echo "--- PX4 failsafe / warnings"; grep -hiE -B2 -A2 "failsafe|warn|error|lost|land|battery|estimat" "$OUT"/sitl-acact-$c-px4-*.log | head -n 120
    [[ "$c" == linkloss ]] && link restore 1 2>/dev/null
    kill "$p0" "$p1" 2>/dev/null; pkill -f "bin/px4" 2>/dev/null
    pkill -f "$KILLPAT" 2>/dev/null; sleep 3; pkill -9 -f "$KILLPAT" 2>/dev/null
    # the GCS writes its own log + summary on exit
    cp -r "$HOME/Documents/MobilityLab/ACACT" "$OUT/acact-logs-$c" 2>/dev/null || true
    kill "$xvfb" 2>/dev/null
    wait 2>/dev/null
    return $rc
}

if [[ "$CASE" != targets ]]; then
    [[ -n "$PX4_BUILD" && -x "$PX4_BUILD/bin/px4" ]] || { echo "::error::PX4 SITL missing"; exit 1; }
    run_acact "$CASE" || status=1
    exit $status
fi


AP_DIR="$(get_arducopter)"
if [[ -n "$AP_DIR" ]]; then
    run_fw ardupilot \
        "./arducopter --model quad --speedup 1 --home 37.2100,126.8300,20,0 --defaults copter.parm,extra.parm -I0 --serial0 udpclient:127.0.0.1:14550 --serial1 udpclient:127.0.0.1:14551" \
        "$AP_DIR" "udpin:0.0.0.0:14551" || status=1
else
    echo "::warning::ArduCopter SITL binary could not be downloaded"
    echo '{"fw":"ardupilot","checks":{},"notes":["SITL binary download failed"]}' > "$OUT/sitl-ardupilot.json"
    status=1
fi

if [[ -n "$PX4_BUILD" && -x "$PX4_BUILD/bin/px4" ]]; then
    rm -rf "$PX4_BUILD/rootfs" && mkdir -p "$PX4_BUILD/rootfs"
    run_fw px4 \
        "PX4_SIM_MODEL=sihsim_quadx PX4_HOME_LAT=37.21 PX4_HOME_LON=126.83 PX4_HOME_ALT=20 ../bin/px4 -d ../etc" \
        "$PX4_BUILD/rootfs" "udpin:0.0.0.0:14540" || status=1
else
    echo "::warning::PX4 SITL not available"
    echo '{"fw":"px4","checks":{},"notes":["PX4 SITL build missing"]}' > "$OUT/sitl-px4.json"
    status=1
fi

echo "=================== SITL summary"
cat "$OUT"/sitl-*.json
exit $status
