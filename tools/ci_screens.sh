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

python3 -m pip install --quiet --user pymavlink || python3 -m pip install --quiet --break-system-packages pymavlink

run_case () {
    local name="$1" size="$2" scenario="$3"
    local disp=":$((90 + RANDOM % 9))"
    echo "=== $name ($size, $scenario) on $disp"

    Xvfb "$disp" -screen 0 "${size}x24" -nolisten tcp &
    local xvfb=$!
    sleep 2

    python3 mlgcs/tools/fake_vehicle.py --scenario "$scenario" --duration 150 > "$OUT/$name-vehicle.log" 2>&1 &
    local veh=$!

    DISPLAY="$disp" QT_QPA_PLATFORM=xcb "$BIN" --clear-settings --swrast > "$OUT/$name-app.log" 2>&1 &
    local app=$!

    sleep 45
    DISPLAY="$disp" import -window root "$OUT/$name-1.png" || true
    sleep 30
    DISPLAY="$disp" import -window root "$OUT/$name-2.png" || true

    kill "$app" "$veh" 2>/dev/null
    sleep 2
    kill -9 "$app" 2>/dev/null
    kill "$xvfb" 2>/dev/null
    wait 2>/dev/null
}

run_case desktop1080 1920x1080 faults
run_case laptop768   1366x768  normal

echo "=== QML problems in our files"
grep -h -E "MobilityLab|/Custom/qml|ML[A-Z][A-Za-z]+\.qml" "$OUT"/*-app.log | sort | uniq -c | sort -rn | head -60 || true
echo "=== QML errors (any)"
grep -h -i -E "qml.*(error|TypeError|ReferenceError|is not a type|Cannot assign)" "$OUT"/*-app.log | sort | uniq -c | sort -rn | head -40 || true
ls -la "$OUT"
