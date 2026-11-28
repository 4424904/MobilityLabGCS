#!/usr/bin/env bash
# Demo-mode check of the AppImage (no simulator needed):
#   1. MLGCS_DEMO=duo starts the built-in demo; the automatic demonstration uploads the demo missions,
#      runs the mission check and the pre-flight check, starts ACACT and takes off both vehicles.
#   2. ACACT must take over (회피 개입) and hand back (회피 완료) on the demo vehicles — the real
#      guard code on simulated aircraft.
#   3. Separation: during the demo a third "aircraft" (raw MAVLink heartbeats, sysid 3, to UDP 14550)
#      must NOT connect; after the demo ends (MLGCS_DEMO_SECONDS) it must connect.
#   4. A demo flight is never recorded as a SITL validation.
#   5. Flight records (v1.2): the demo flight is recorded under Records/Demo (never Flights/), the
#      track has rows, the record loads and exports a PDF and CSV, and the on-ground AGL is ~0 m
#      (demo home altitude taken from the terrain database, not a fixed number).
#   0. Before all that, a short first launch with the "aircraft" already connected: the demo must
#      refuse to start (it never drops a real aircraft's link on its own).
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
shot () { python3 -c "from PIL import ImageGrab; ImageGrab.grab(xdisplay=':61').save('$OUT/$1.png')" || true; }
launch () { sg dialout -c "MLGCS_DEMO_DELAY_MS=${2:-4000} ML_TEST_ACACT_CASE=none MLGCS_DEMO=duo MLGCS_DEMO_AUTO=1 MLGCS_DEMO_SECONDS=$DEMO_S MLGCS_REC_SELFTEST=1 ML_TEST_ACACT=1 DISPLAY=:61 QT_QPA_PLATFORM=xcb LIBGL_ALWAYS_SOFTWARE=1 '$BIN' > '$1' 2>&1" & }
stop_app () {
    pkill -INT -f "$W/squashfs-root" 2>/dev/null
    for _ in $(seq 1 20); do pgrep -f "$W/squashfs-root" > /dev/null || break; sleep 1; done
    pkill -9 -f "$W/squashfs-root" 2>/dev/null; sleep 2
}

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
has () { grep -qE "$1" "$LOG" 2>/dev/null; }
wait_for () { local end=$((SECONDS + $2)); while (( SECONDS < end )); do has "$1" && return 0; sleep 1; done; return 1; }

# ---- launch 0: real aircraft connected first → demo start refused ---------------------------------
ok_refuse=false
LOG="$OUT/demo-refuse.log"
python3 "$W/intruder.py" & INTR=$!
launch "$LOG" 12000
if wait_for "MLDEMO blocked" 60 && ! has "MLDEMO active true"; then ok_refuse=true; fi
sleep 3; shot demo-refused
kill $INTR 2>/dev/null; stop_app

# ---- launch 1: the demo itself; the aircraft appears only once the demo runs ----------------------
LOG="$OUT/demo-app.log"
launch "$LOG"
wait_for "MLDEMO active true" 60
python3 "$W/intruder.py" & INTR=$!

ok_auto=false; ok_take=false; ok_rel=false; ok_block=true; ok_after=false; ok_norec=true
wait_for "MLDEMO auto \| .*일괄 이륙" 240 && ok_auto=true
sleep 25; shot demo-flying
wait_for "MLACACT D[12] \| 회피 개입" 240 && ok_take=true
sleep 3; shot demo-avoid
wait_for "MLACACT D[12] \| 회피 완료" 120 && ok_rel=true
sleep 5; shot demo-after-avoid
# during the demo the intruder (sysid 3) must never have been attached
has "MLVEHICLE added 3" && ok_block=false
has "MLDEMO active true" || ok_block=false          # only meaningful if the demo really ran
# end of demo → real links allowed → the intruder connects
end=$((SECONDS + DEMO_S + 120))
while (( SECONDS < end )); do has "MLVEHICLE added 3" && { ok_after=true; break; }; sleep 2; done
shot demo-ended
has "SITL 검증 기록" && ok_norec=false
kill $INTR 2>/dev/null; stop_app
grep -E "MLACACT|MLDEMO|MLVEHICLE|MLREC|blocked \(demo" "$LOG" | head -300 > "$OUT/demo-events.txt"
# ---- flight records -------------------------------------------------------------------------------
REC="$HOME/Documents/MobilityLab/Records"
ls -laR "$REC" > "$OUT/records-tree.txt" 2>&1 || true
RECJSON=$(python3 - "$REC" "$LOG" <<'PY'
import sys, os, json, glob, csv
rec, log = sys.argv[1], open(sys.argv[2], errors="replace").read()
demo = sorted(glob.glob(os.path.join(rec, "Demo", "*", "meta.json")))
real = glob.glob(os.path.join(rec, "Flights", "*"))
c = {"rec_demo_created": False, "rec_no_real_record_from_demo": len(real) == 0, "rec_track_rows": False,
     "rec_load_export": False, "agl_on_ground_near_zero": False}
m = {"demo_records": len(demo), "flight_records": len(real)}
if demo:
    d = os.path.dirname(demo[-1]); meta = json.load(open(demo[-1], encoding="utf-8"))
    c["rec_demo_created"] = meta.get("kind") == "demo" and bool(meta.get("ended"))
    rows = list(csv.DictReader(open(os.path.join(d, "track.csv"), encoding="utf-8-sig")))
    m["track_rows"] = len(rows); c["rec_track_rows"] = len(rows) > 100
    pdf, scsv = os.path.join(d, "report.pdf"), os.path.join(d, "summary.csv")
    c["rec_load_export"] = ("MLREC export pdf FAIL" not in log and os.path.exists(pdf) and os.path.getsize(pdf) > 10000
                            and os.path.exists(scsv) and os.path.getsize(scsv) > 50)
    m["pdf_bytes"] = os.path.getsize(pdf) if os.path.exists(pdf) else 0
    g = [float(r["agl"]) for r in rows if r.get("agl") not in ("", None) and r.get("alt_rel") not in ("", None)
         and abs(float(r["alt_rel"])) < 0.5]
    if g:
        m["agl_ground_min"], m["agl_ground_max"] = round(min(g), 2), round(max(g), 2)
        c["agl_on_ground_near_zero"] = min(g) > -1.5 and max(g) < 1.5
    for e in ("events.csv",):
        m["events_rows"] = sum(1 for _ in open(os.path.join(d, e), encoding="utf-8-sig")) - 1
m["terrain_line"] = next((l.split("MLDEMO terrain",1)[1].strip()[:80] for l in log.splitlines() if "MLDEMO terrain" in l), "")
print(json.dumps({"c": c, "m": m}))
PY
)
echo "$RECJSON" > "$OUT/records-check.json"
cat > "$OUT/sitl-demo.json" <<JSON
{"case":"demo","checks":{"demo_refused_with_real_vehicle":$ok_refuse,"auto_demo_started":$ok_auto,"acact_takeover_on_demo":$ok_take,"acact_release_on_demo":$ok_rel,
 "real_link_blocked_during_demo":$ok_block,"real_link_allowed_after_demo":$ok_after,"no_sitl_record_from_demo":$ok_norec},"metrics":{}}
JSON
python3 - "$OUT/sitl-demo.json" "$OUT/records-check.json" <<'PY'
import json, sys
a = json.load(open(sys.argv[1]))
try: r = json.load(open(sys.argv[2]))
except Exception: r = {"c": {"rec_check_ran": False}, "m": {}}
a["checks"].update(r["c"]); a["metrics"].update(r["m"])
json.dump(a, open(sys.argv[1], "w"), ensure_ascii=False)
PY
cat "$OUT/sitl-demo.json"
# the job fails when any check fails
grep -q '": *false' "$OUT/sitl-demo.json" && { echo "demo check FAILED"; exit 1; }
echo "demo checks PASS"
