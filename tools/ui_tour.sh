#!/usr/bin/env bash
# UI tour of a released build: two PX4 SIH quadcopters, the GCS operated through its own UI (mouse clicks
# with xdotool) plus the built-in CI operator driver (ML_TEST_ACACT_CASE=user). Screenshots at 1920x1080,
# a second 1920x1080 "monitor" to the right for the detached windows, and a video of the whole run.
#   usage: ui_tour.sh <MobilityLabGCS.AppImage> <px4 sitl dir (bin/, etc/)> <out dir>
set -uo pipefail
APP="$1"; PX4="$2"; mkdir -p "$3"; OUT="$(cd "$3" && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"
export DISPLAY=:55
W="$(mktemp -d)"
LOG="$OUT/app.log"
step=0

(cd "$W" && "$APP" --appimage-extract > /dev/null)
BIN="$W/squashfs-root/AppRun"
sudo usermod -a -G dialout "$USER" || true

Xvfb :55 -screen 0 3840x1080x24 -nolisten tcp > /dev/null 2>&1 &
sleep 2
ffmpeg -loglevel error -f x11grab -video_size 1920x1080 -framerate 8 -i :55+0,0 \
    -c:v libx264 -preset veryfast -crf 34 -pix_fmt yuv420p "$OUT/tour.mp4" &
FFMPEG=$!

shot () {   # shot <name> [full]  (main monitor, or both monitors with "full")
    step=$((step + 1))
    local f; f="$OUT/$(printf '%02d' $step)_$1.png"
    if [[ "${2:-}" == full ]]; then import -window root "$f"; else import -window root -crop 1920x1080+0+0 +repage "$f"; fi
    echo "shot $f"
}
click () { xdotool mousemove "$1" "$2" click 1; sleep "${3:-1.5}"; }
typein () { xdotool type --delay 40 "$1"; sleep 0.5; }
waitlog () { local end=$((SECONDS + $2)); while (( SECONDS < end )); do grep -qE "$1" "$LOG" 2>/dev/null && return 0; sleep 0.3; done; echo "timeout: $1"; return 1; }
maximise () { for w in $(xdotool search --onlyvisible --name "MobilityLabGCS$" 2>/dev/null); do xdotool windowmove "$w" 0 0 windowsize "$w" 1920 1080; done; }
dismiss_qgc_popup () {   # QGC "Configuration tasks remain…" (SITL vehicles are not set up): Escape, then the OK button if one is there
    xdotool key Escape; sleep 0.5
    local px; px=$(import -window root -crop 1x1+1262+522 -depth 8 txt:- | grep -oE 'srgb\([0-9,]+\)' | tr -dc '0-9,')
    IFS=, read -r r g b <<< "$px"; (( b > r + 80 )) && click 1262 522 1
    return 0
}

# settings: Esri imagery (the VWorld key only serves Korean IPs), 3D viewer enabled
rm -rf "$HOME/.config/MobilityLab" "$HOME/Documents/MobilityLab"
mkdir -p "$HOME/.config/MobilityLab"
printf '[FlightMap]\nmapProvider=Esri\nmapType=World Satellite\n[Viewer3D]\nenabled=true\n' > "$HOME/.config/MobilityLab/MobilityLabGCS.ini"
python3 "$HERE/acact_sitl.py" --make-plans "$OUT/plans" > /dev/null

# ---- 1. start ----------------------------------------------------------------------------------
sg dialout -c "ML_TEST_ACACT=1 ML_TEST_ACACT_N=2 ML_TEST_ACACT_CASE=user ML_TEST_PLAN_DIR='$OUT/plans' DISPLAY=:55 QT_QPA_PLATFORM=xcb LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=2 nice -n 10 '$BIN' > '$LOG' 2>&1" &
sleep 3; shot startup
sleep 9; maximise; sleep 4; shot main_no_vehicle

px4 () {   # px4 <instance> <lon> <rtl alt>
    local d="$PX4/rootfs$1"; rm -rf "$d"; mkdir -p "$d"
    (cd "$d" && PX4_SIM_MODEL=sihsim_quadx PX4_PARAM_COM_OF_LOSS_T=1.0 PX4_PARAM_COM_OBL_RC_ACT=5 PX4_PARAM_NAV_ACC_RAD=2.0 \
        PX4_PARAM_MPC_TKO_SPEED=1.0 PX4_PARAM_MPC_XY_CRUISE=3.0 PX4_PARAM_MIS_TAKEOFF_ALT=8.0 PX4_PARAM_RTL_CONE_ANG=0 \
        PX4_PARAM_COM_RC_IN_MODE=4 PX4_PARAM_NAV_RCL_ACT=0 PX4_PARAM_COM_RCL_EXCEPT=7 PX4_PARAM_NAV_DLL_ACT=0 PX4_PARAM_SIM_BAT_DRAIN=1800 \
        PX4_PARAM_SIH_LOC_LAT0=37.2100856 PX4_PARAM_SIH_LOC_LON0="$2" PX4_PARAM_RTL_RETURN_ALT="$3" ../bin/px4 -i "$1" -d ../etc) \
        > "$OUT/px4-$1.log" 2>&1 &
    sleep 3
    for pid in $(pgrep -f "bin/px4"); do for t in /proc/$pid/task/*; do sudo renice -n -10 -p "${t##*/}" > /dev/null 2>&1; done; done
}

# ---- 2. one vehicle ----------------------------------------------------------------------------
px4 0 126.8307462 20
sleep 35; dismiss_qgc_popup; sleep 3
shot single_vehicle
# 3D view (tool strip, second button once the 3D viewer is enabled)
click 455 145 25; shot 3d_view
click 455 145 4

# ---- 3. second vehicle: the operator driver loads user missions (a wrong D2 mission first) ----------
click 1782 931 2                       # open the ACACT console (one vehicle: fleet bar at y 931)
px4 1 126.8309154 26
sleep 25; dismiss_qgc_popup
click 1050 126 1                       # 운용 tab
shot multi_vehicle_ground
if waitlog "bad mission errors=" 120; then
    click 1103 126 0.8; shot mission_check_errors          # 미션 검사 tab: D2 takeoff point 30 m off → start blocked
    click 1168 126 0.8; shot preflight_blocked             # 사전 점검 tab
fi
if waitlog "mission check errors=0" 120; then
    click 1103 126 1.5; shot mission_check_warnings        # correct D2 mission: crossing tracks = caution only
fi
click 1050 126 1
waitlog "일괄 시작:" 60; sleep 12; shot multi_vehicle_flying

# ---- 4. ACACT conflict prediction and avoidance ------------------------------------------------
if waitlog "MLACACT D[0-9] \| 회피 개입" 300; then
    sleep 1.5; shot acact_avoidance_console
    click 1478 91 2; shot acact_avoidance_map              # console closed: map overlay only
    click 1782 892 1
fi
# ---- 5. link loss of D2 after its avoidance ----------------------------------------------------
if waitlog "MLACACT D2 \| 회피 완료" 200; then
    sleep 1
    sudo iptables -I INPUT -i lo -p udp --sport 18571 -j DROP; sudo iptables -I INPUT -i lo -p udp --dport 18571 -j DROP
    sleep 5; shot link_loss_warning
    sleep 4; click 1478 91 1.5; shot link_loss_map; click 1782 892 1
    sudo iptables -D INPUT -i lo -p udp --sport 18571 -j DROP; sudo iptables -D INPUT -i lo -p udp --dport 18571 -j DROP
    sleep 6; shot link_restored
fi
waitlog "SITL 검증 기록" 400; sleep 3; shot flight_complete

# ---- 6. stop the guard, analysis + replay + PDF ------------------------------------------------
click 1050 126 1; click 1069 174 3                         # 가드 종료
click 1478 91 1                                            # close console
click 1865 892 3; shot analysis_sessions
click 570 178 3; shot analysis_loaded
click 1002 658 1; click 750 658 1                          # 16×, play
for i in 1 2 3 4 5 6; do sleep 4; shot "analysis_replay_$i"; done
click 1331 90 2; click 882 724 1; typein "ACACT_report"; click 1077 769 4
shot analysis_after_pdf
cp "$HOME"/Documents/MobilityLab/ACACT/ACACT_report.pdf "$OUT/ACACT_report.pdf" 2>/dev/null && \
    pdftoppm -r 110 -png "$OUT/ACACT_report.pdf" "$OUT/pdf_page"
click 1480 90 2                                            # close analysis

# ---- 7. mission create / edit (QGC plan view of D1) --------------------------------------------
click 1673 606 4; shot plan_view
click 1706 231 2; shot plan_edit_item
click 34 175 1; click 700 420 1; click 820 300 1; click 1000 360 2; shot plan_add_waypoints
click 22 20 1; click 60 73 4; dismiss_qgc_popup

# ---- 8. vehicle profiles and settings ------------------------------------------------------------
click 1782 892 2; click 1222 126 2
click 1110 338 0.5; typein "X500-1"; xdotool key Return
click 1355 338 0.5; typein "15"; xdotool key Return; sleep 1
shot settings_profiles
xdotool mousemove 1250 700; for i in 1 2 3 4 5 6; do xdotool click 5; done; sleep 1; shot settings_params

# ---- 9. English ---------------------------------------------------------------------------------
xdotool mousemove 1250 400; for i in 1 2 3 4 5 6; do xdotool click 4; done; sleep 1
click 1447 174 2; shot english_restart_notice; click 1262 522 2
shot english_settings
click 1050 126 2; shot english_operate
click 1478 91 1; click 1865 892 3; click 570 178 3; shot english_analysis; click 1480 90 2
click 1782 892 2; click 1280 126 2; click 1397 174 2; click 1262 522 2       # back to Korean
shot korean_again

# ---- 10. dual monitor: console and analysis in their own windows on the second screen ------------
click 1418 91 3                                             # console → 새 창
click 1865 892 3; click 1420 90 3                           # analysis → 새 창
for w in $(xdotool search --onlyvisible --name "ACACT$" 2>/dev/null); do xdotool windowmove "$w" 1920 0 windowsize "$w" 640 1080; done
for w in $(xdotool search --onlyvisible --name "비행 분석" 2>/dev/null); do xdotool windowmove "$w" 2560 0 windowsize "$w" 1280 1080; done
sleep 3
for w in $(xdotool search --onlyvisible --name "비행 분석" 2>/dev/null); do xdotool mousemove 2600 200 click 1; done; sleep 2
shot dual_monitor full

kill -INT "$FFMPEG"; sleep 3
pkill -f "bin/px4"; pkill -f "$W/squashfs-root"
ls -la "$OUT"
