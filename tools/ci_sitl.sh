#!/usr/bin/env bash
# Fly ArduPilot (ArduCopter SITL) and PX4 (SIH quadcopter) against MobilityLab GCS
# and check the 목표 조정 (heading / altitude / speed) commands reach the aircraft.
#   usage: ci_sitl.sh <qgc-build-dir> <output-dir> <px4-build-dir or "">
# Writes sitl-<fw>.json, sitl-<fw>-*.png and logs to <output-dir>.
set -uo pipefail

BUILD_DIR="$1"
OUT="$2"
PX4_BUILD="${3:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$OUT"
WORK="$(mktemp -d)"

BIN="$(find "$BUILD_DIR" -maxdepth 3 -type f -name MobilityLabGCS -perm -u+x | head -n1)"
[[ -z "$BIN" ]] && { echo "::error::MobilityLabGCS binary not found"; exit 1; }

python3 -m pip install --quiet pymavlink pillow "mavsdk<4" numpy || python3 -m pip install --quiet --break-system-packages pymavlink pillow "mavsdk<4" numpy
# ACACT guard run by the GCS itself (PX4 run): GCS starts guard.py, bridges the vehicle to its mavsdk_server
GUARD_DIR="$WORK/acact_guard"
cp -r "$HERE/../integrations/acact_guard/src" "$GUARD_DIR"

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
    if [[ -n "$extra_env" ]]; then
        echo "--- $fw guard (run by the GCS)"
        grep -h "MLGUARD\|GuardRouter\|guard runs locally\|guard |" "$OUT/sitl-$fw-app.log" > "$OUT/sitl-$fw-guard.txt" || true
        tail -n 40 "$OUT/sitl-$fw-guard.txt"
    fi

    kill "$sim" 2>/dev/null; pkill -f arducopter 2>/dev/null; pkill -f "bin/px4" 2>/dev/null
    pkill -f "$BIN" 2>/dev/null; sleep 2; pkill -9 -f "$BIN" 2>/dev/null
    kill "$xvfb" 2>/dev/null
    wait 2>/dev/null
    return $rc
}

status=0

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
        "$PX4_BUILD/rootfs" "udpin:0.0.0.0:14540" "ACACT_GUARD_DIR='$GUARD_DIR' ACACT_PYTHON=python3" || status=1
    pkill -f mavsdk_server 2>/dev/null
else
    echo "::warning::PX4 SITL not available"
    echo '{"fw":"px4","checks":{},"notes":["PX4 SITL build missing"]}' > "$OUT/sitl-px4.json"
    status=1
fi

echo "=================== SITL summary"
cat "$OUT"/sitl-*.json
exit $status
