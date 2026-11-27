#!/usr/bin/env bash
# Screen-capture tour of a built AppImage. The GCS runs its own tour driver (ML_TOUR=1,
# MLTourDriver.qml) on the built-in demo vehicles and prints "MLTOUR shot <name>" when a screen
# is ready; this script captures it. 1920x1080 main monitor (+ a second 1920x1080 monitor to the
# right for the detached windows) with a video of the whole run, then the start of the tour again
# at 2560x1440 and 3840x2160 (scaling check).
#   usage: ui_tour.sh <MobilityLabGCS.AppImage> <out dir>
set -uo pipefail
APP="$1"; mkdir -p "$2"; OUT="$(cd "$2" && pwd)"
W="$(mktemp -d)"
(cd "$W" && "$APP" --appimage-extract > /dev/null)
BIN="$W/squashfs-root/AppRun"
sudo usermod -a -G dialout "$USER" || true

seed () {
    rm -rf "$HOME/.config/MobilityLab" "$HOME/Documents/MobilityLab"
    mkdir -p "$HOME/.config/MobilityLab"
    printf '[FlightMap]\nmapProvider=Esri\nmapType=World Satellite\n[Viewer3D]\nenabled=true\n' > "$HOME/.config/MobilityLab/MobilityLabGCS.ini"
}
run_app () {   # run_app <display> <log>
    sg dialout -c "ML_TOUR=1 ML_TEST_ACACT=1 ML_TEST_ACACT_CASE=none DISPLAY=$1 QT_QPA_PLATFORM=xcb LIBGL_ALWAYS_SOFTWARE=1 '$BIN' > '$2' 2>&1" &
}
maximise () {  # maximise <display> <w> <h>   (main window only: class MobilityLabGCS, title exactly "MobilityLabGCS")
    for w in $(DISPLAY=$1 xdotool search --class "MobilityLabGCS" 2>/dev/null); do
        [[ "$(DISPLAY=$1 xdotool getwindowname "$w" 2>/dev/null)" == "MobilityLabGCS" ]] || continue
        DISPLAY=$1 xdotool windowmove "$w" 0 0 windowsize "$w" "$2" "$3" 2>/dev/null
    done
}

# ---- main run: 1920x1080 + second monitor -----------------------------------------------------
seed
Xvfb :55 -screen 0 3840x1080x24 -nolisten tcp > /dev/null 2>&1 &
sleep 2
LOG="$OUT/tour-app.log"
run_app :55 "$LOG"
ffmpeg -loglevel error -f x11grab -video_size 1920x1080 -framerate 10 -i :55+0,0 \
    -c:v libx264 -preset veryfast -crf 30 -pix_fmt yuv420p "$OUT/MobilityLabGCS-v1.0-demo-tour.mp4" &
FF=$!
seen=""
stop_app() {   # the next run refuses to start while any instance is alive
    pkill -INT -f squashfs-root/ 2>/dev/null
    for _ in $(seq 1 20); do pgrep -f squashfs-root/ > /dev/null || break; sleep 1; done
    pkill -9 -f squashfs-root/ 2>/dev/null; sleep 2
}
keys_done=0
end=$((SECONDS + 1800))
while (( SECONDS < end )); do
    sleep 0.5
    (( SECONDS % 5 == 0 )) && maximise :55 1920 1080
    while read -r name; do
        [[ " $seen " == *" $name "* ]] && continue
        seen="$seen $name"
        if [[ "$name" == "25_dual_monitor" ]]; then
            for w in $(DISPLAY=:55 xdotool search --onlyvisible --name "비행 계기" 2>/dev/null); do DISPLAY=:55 xdotool windowmove "$w" 1920 0 windowsize "$w" 640 1080; done
            for w in $(DISPLAY=:55 xdotool search --onlyvisible --name "기체 시스템" 2>/dev/null); do DISPLAY=:55 xdotool windowmove "$w" 2580 0 windowsize "$w" 640 1080; done
            sleep 2
            DISPLAY=:55 import -window root "$OUT/$name.png"
        else
            maximise :55 1920 1080; sleep 0.7
            DISPLAY=:55 import -window root -crop 1920x1080+0+0 +repage "$OUT/$name.png"
        fi
        echo "captured $name"
    done < <(grep -o "MLTOUR shot [0-9a-z_]*" "$LOG" 2>/dev/null | awk '{print $3}')
    # keys the tour asks for (closing QGC's own dialogs: mission complete, restart notice)
    nk=$(grep -c "MLTOUR key " "$LOG" 2>/dev/null); nk=${nk:-0}
    while (( keys_done < nk )); do
        keys_done=$((keys_done + 1))
        k=$(grep "MLTOUR key " "$LOG" | sed -n "${keys_done}p" | grep -o "key [A-Za-z]*" | awk '{print $2}')
        DISPLAY=:55 xdotool key "$k"; echo "key $k"
    done
    grep -q "MLTOUR done" "$LOG" && break
done
sleep 2
kill -INT $FF; sleep 3
pdf="$(grep -o 'MLTOUR pdf .*' "$LOG" | head -1 | sed -e 's/MLTOUR pdf //' -e 's/ - qml - .*//')"
if [[ -n "$pdf" && -f "$pdf" ]]; then
    cp "$pdf" "$OUT/ACACT_report_demo.pdf"
    pdftoppm -r 100 -png "$OUT/ACACT_report_demo.pdf" "$OUT/31_pdf_page"
fi
stop_app
grep -E "MLTOUR|MLDEMO|MLACACT|MLVEHICLE" "$LOG" > "$OUT/tour-events.txt"

# ---- scaling: QHD and 4K (start of the tour only) ------------------------------------------------
for res in 2560x1440 3840x2160; do
    seed
    Xvfb :56 -screen 0 ${res}x24 -nolisten tcp > /dev/null 2>&1 & XV=$!
    sleep 2
    L="$OUT/tour-$res.log"
    run_app :56 "$L"
    end=$((SECONDS + 300)); got=""
    while (( SECONDS < end )); do
        sleep 1
        maximise :56 "${res%x*}" "${res#*x}"
        for n in 03_standard_no_vehicle 09_standard_single_flying 12_advanced_single; do
            if grep -q "MLTOUR shot $n" "$L" && [[ " $got " != *" $n "* ]]; then
                sleep 1; DISPLAY=:56 import -window root "$OUT/scale_${res}_$n.png"; got="$got $n"
            fi
        done
        [[ "$got" == *12_advanced_single* ]] && break
    done
    stop_app; kill $XV 2>/dev/null; sleep 1
done
ls -la "$OUT"
