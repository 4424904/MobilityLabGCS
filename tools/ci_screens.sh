#!/usr/bin/env bash
# Start MobilityLab GCS under a virtual display, feed it a simulated tandem
# helicopter, and save screenshots plus the application log.
#   usage: ci_screens.sh <build-dir> <output-dir>
set -uo pipefail

BUILD_DIR="$1"
OUT="$2"
mkdir -p "$OUT"

BIN="$(find "$BUILD_DIR" -maxdepth 3 -type f -name MobilityLabGCS -perm -u+x | head -n1)"
if [[ -z "$BIN" ]]; then
    echo "::error::MobilityLabGCS binary not found in $BUILD_DIR"
    find "$BUILD_DIR" -maxdepth 2 -type f -perm -u+x | head -n 20
    exit 1
fi
echo "Binary: $BIN"
echo "=== Missing shared libraries (should be empty)"
ldd "$BIN" | grep "not found" || true

python3 -m pip install --quiet pymavlink pillow || python3 -m pip install --quiet --break-system-packages pymavlink pillow
python3 -c "import pymavlink, PIL; print('pymavlink/pillow ok')"

shot () {
    python3 -c "from PIL import ImageGrab; ImageGrab.grab(xdisplay='$1').save('$2')" || echo "screenshot failed: $2"
}

# Linux-only "serial port permission" dialog: put the runner user in dialout
sudo usermod -a -G dialout "$USER" || true

seed_settings () {
    # Fresh settings per case. The VWorld key only serves Korean IPs, so the
    # cloud runner uses Esri imagery to judge legibility over a real map.
    rm -rf "$HOME/.config/MobilityLab"
    mkdir -p "$HOME/.config/MobilityLab"
    for f in MobilityLabGCS.ini MobilityLabGCS.conf; do
        printf '[FlightMap]\nmapProvider=Esri\nmapType=World Satellite\n' > "$HOME/.config/MobilityLab/$f"
    done
}

run_case () {
    local name="$1" size="$2" scenario="$3" airframe="${4:-tandem}" second="${5:-}"
    local disp=":$((90 + RANDOM % 9))"
    echo "=== $name ($size, $scenario) on $disp"

    Xvfb "$disp" -screen 0 "${size}x24" -nolisten tcp &
    local xvfb=$!
    sleep 2

    python3 mlgcs/tools/fake_vehicle.py --scenario "$scenario" --airframe "$airframe" --duration 150 > "$OUT/$name-vehicle.log" 2>&1 &
    local veh=$!
    local veh2=""
    if [ -n "$second" ]; then
        # second vehicle (system id 2) to check the multi-vehicle view
        # started late so the first vehicle stays the active one
        (sleep 25; python3 mlgcs/tools/fake_vehicle.py --sysid 2 --scenario normal --airframe "$second" --duration 120 > "$OUT/$name-vehicle2.log" 2>&1) &
        veh2=$!
    fi

    seed_settings
    sg dialout -c "DISPLAY='$disp' QT_QPA_PLATFORM=xcb LIBGL_ALWAYS_SOFTWARE=1 '$BIN' > '$OUT/$name-app.log' 2>&1" &
    local app=$!

    # No window manager under Xvfb: maximise by hand
    sleep 12
    DISPLAY="$disp" xdotool search --onlyvisible --name ".*" 2>/dev/null | while read -r w; do
        echo "window $w: $(DISPLAY="$disp" xdotool getwindowname "$w" 2>/dev/null)"
        DISPLAY="$disp" xdotool windowmove "$w" 0 0 windowsize "$w" 100% 100% || true
    done

    sleep 33
    shot "$disp" "$OUT/$name-1.png"
    sleep 30
    shot "$disp" "$OUT/$name-2.png"

    kill "$veh" 2>/dev/null
    [ -n "$veh2" ] && kill "$veh2" 2>/dev/null
    pkill -f fake_vehicle.py 2>/dev/null
    pkill -f "$BIN" 2>/dev/null
    sleep 2
    pkill -9 -f "$BIN" 2>/dev/null
    kill "$xvfb" 2>/dev/null
    wait 2>/dev/null
}

run_case tandem1080 1920x1080 faults tandem quad
run_case quad768    1366x768  normal quad

echo "=== QML problems in our files"
grep -h -E "MobilityLab|/Custom/qml|ML[A-Z][A-Za-z]+\.qml" "$OUT"/*-app.log | sort | uniq -c | sort -rn | head -60 || true
echo "=== QML errors (any)"
grep -h -i -E "qml.*(error|TypeError|ReferenceError|is not a type|Cannot assign)" "$OUT"/*-app.log | sort | uniq -c | sort -rn | head -40 || true
ls -la "$OUT"
