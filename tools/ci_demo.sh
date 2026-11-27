#!/usr/bin/env bash
# Demo-mode check of the AppImage (no simulator needed):
#   1. MLGCS_DEMO=duo starts the built-in demo; the automatic demonstration uploads the demo missions,
#      runs the mission check and the pre-flight check, starts ACACT and takes off both vehicles.
#   2. ACACT must take over (회피 개입) and hand back (회피 완료) on the demo vehicles — the real
#      guard code on simulated aircraft.
#   3. Separation: during the demo a third "aircraft" (raw MAVLink heartbeats, sysid 3, to UDP 14550)
#      must NOT connect; after the demo ends (MLGCS_DEMO_SECONDS) it must connect.
#   4. A demo flight is never recorded as a SITL validation.
#   usage: ci_demo.sh <MobilityLabGCS.AppImage> <out dir>
set -uo pipefail
APP="$1"; mkdir -p "$2"; OUT="$(cd "$2" && pwd)"
chmod +x "$APP"
W="$(mktemp -d)"; (cd "$W" && "$APP" --appimage-extract > /dev/null)
BIN="$W/squashfs-root/AppRun"
sudo usermod -a -G dialout "$USER" || true
python3 -m pip install --quiet pillow || python3 -m pip install --quiet --break-system-packages pillow
rm -rf "$HOME/.config/MobilityLab" "$HOME/Documents/MobilityLab"; mkdir -p "$HOME/.config/MobilityLab"
printf '[FlightMap]\nmapProvider=Esri\nmapType=World Satellite\n' > "$HOME/.config/MobilityLab/MobilityLabGCS.ini"
export DISPLAY=:61
Xvfb :61 -screen 0 1920x1080x24 -nolisten tcp > /dev/null 2>&1 &
sleep 2
LOG="$OUT/demo-app.log"
DEMO_S=420
sg dialout -c "ML_TEST_ACACT_CASE=none MLGCS_DEMO=duo MLGCS_DEMO_AUTO=1 MLGCS_DEMO_SECONDS=$DEMO_S ML_TEST_ACACT=1 DISPLAY=:61 QT_QPA_PLATFORM=xcb LIBGL_ALWAYS_SOFTWARE=1 '$BIN' > '$LOG' 2>&1" &
shot () { python3 -c "from PIL import ImageGrab; ImageGrab.grab(xdisplay=':61').save('$OUT/$1.png')" || true; }

# intruder: MAVLink v1 heartbeats of sysid 3 to the GCS's auto-connect UDP port, all the time
cat > "$W/intruder.py" <<'PY'
import socket, struct, time
def crc(buf):
    c = 0xFFFF
    for b in buf:
        t = b ^ (c & 0xFF); t = (t ^ (t << 4)) & 0xFF
        c = ((c >> 8) ^ (t << 8) ^ (t << 3) ^ (t >> 4)) & 0xFFFF
    return c
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); seq = 0
while True:
    payload = struct.pack("<IBBBBB", 0, 2, 12, 0, 3, 3)          # custom_mode, QUADROTOR, PX4, base, STANDBY, v3
    hdr = bytes([9, seq & 0xFF, 3, 1, 0])
    c = crc(hdr + payload + bytes([50]))
    s.sendto(bytes([0xFE]) + hdr + payload + struct.pack("<H", c), ("127.0.0.1", 14550))
    seq += 1; time.sleep(0.5)
PY
python3 "$W/intruder.py" & INTR=$!

has () { grep -qE "$1" "$LOG" 2>/dev/null; }
wait_for () { local end=$((SECONDS + $2)); while (( SECONDS < end )); do has "$1" && return 0; sleep 1; done; return 1; }

ok_auto=false; ok_take=false; ok_rel=false; ok_block=true; ok_after=false; ok_norec=true
wait_for "MLDEMO auto \| .*일괄 이륙" 240 && ok_auto=true
sleep 25; shot demo-flying
wait_for "MLACACT D[12] \| 회피 개입" 240 && ok_take=true
sleep 3; shot demo-avoid
wait_for "MLACACT D[12] \| 회피 완료" 120 && ok_rel=true
sleep 5; shot demo-after-avoid
# during the demo the intruder (sysid 3) must never have been attached
has "MLVEHICLE added 3" && ok_block=false
has "demo started" || ok_block=false          # only meaningful if the demo really ran
# end of demo → real links allowed → the intruder connects
end=$((SECONDS + DEMO_S + 120))
while (( SECONDS < end )); do has "MLVEHICLE added 3" && { ok_after=true; break; }; sleep 2; done
shot demo-ended
has "SITL 검증 기록" && ok_norec=false
kill $INTR 2>/dev/null; pkill -f "$W/squashfs-root" ; sleep 2
grep -E "MLACACT|MLDEMO|MLVEHICLE|blocked \(demo" "$LOG" | head -200 > "$OUT/demo-events.txt"
cat > "$OUT/sitl-demo.json" <<JSON
{"case":"demo","checks":{"auto_demo_started":$ok_auto,"acact_takeover_on_demo":$ok_take,"acact_release_on_demo":$ok_rel,
 "real_link_blocked_during_demo":$ok_block,"real_link_allowed_after_demo":$ok_after,"no_sitl_record_from_demo":$ok_norec},"metrics":{}}
JSON
cat "$OUT/sitl-demo.json"
