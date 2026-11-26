#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# demo.sh — 현장에서 명령 하나로 진행하기
#
#   ./demo.sh setup         준비: 기체 연결 → 안전 설정값 적용 → 미션 만들기
#                           (비행 방향은 기체 기수 방향으로 자동. 직접 지정하려면 ./demo.sh setup 30)
#   ./demo.sh fly           비행: 지도 화면 + 가드 실행 (가드에서 load → start)
#   ./demo.sh stop          끝: 모뎀 연결 프로그램 종료
#
# 기본값: 오리건 2대 (D1, D2).  다른 현장/대수는 앞에 붙여서:
#   SITE=hwaseong ./demo.sh setup             화성 시험장 2대
#   SITE=hwaseong DRONES=D1,D2,D3,D4 ./demo.sh setup   화성 4대
#   LINK=radio ./demo.sh setup                USB 텔레메트리 모뎀으로 연결할 때 (router/radio*.conf)
#   LINK=sitl ./demo.sh setup                 집에서 SITL 연습 (./launch_sitl.sh 먼저)
# ─────────────────────────────────────────────────────────────
set -e
cd "$(dirname "$0")"
SITE=${SITE:-oregon2}
DRONES=${DRONES:-D1,D2}
LINK=${LINK:-wifi}           # wifi = 와이파이 공유기(UDP, 기본), radio = 텔레메트리 모뎀(USB)
VENV=~/acact-venv/bin/activate

say(){ echo; echo "▶ $1"; }
die(){ echo; echo "✖ $1"; exit 1; }

[ -f "$VENV" ] || die "설치가 안 되어 있습니다. 먼저: bash install.sh"
# shellcheck disable=SC1090
source "$VENV"

start_routers(){
  if [ "$LINK" = "sitl" ]; then echo "  SITL: 연결 프로그램 필요 없음"; return; fi
  for id in ${DRONES//,/ }; do
    n=${id#D}
    if [ "$LINK" = "wifi" ]; then conf="router/wifi$n.conf"; else conf="router/radio$n.conf"; fi
    if [ "$LINK" != "wifi" ] && grep -q REPLACE_WITH "$conf"; then die "$conf 에 모뎀 주소가 없습니다 (가이드 3장 ⑤)"; fi
    if pgrep -f "mavlink-routerd -c $conf" >/dev/null; then
      echo "  $id ($LINK): 이미 연결됨"
    else
      mavlink-routerd -c "$conf" > "/tmp/router_$id.log" 2>&1 &
      sleep 1
      pgrep -f "mavlink-routerd -c $conf" >/dev/null || die "$id 모뎀 연결 실패 — /tmp/router_$id.log 확인, 모뎀 USB 확인"
      echo "  $id ($LINK): 연결"
    fi
  done
}

case "$1" in
  setup)
    BEARING=${2:-auto}
    if [ "$BEARING" = "auto" ]; then BTXT="자동 (기체 기수 방향)"; else BTXT="$BEARING°"; fi
    say "현장: $SITE / 기체: $DRONES / 비행 방향: $BTXT"
    say "1/3 기체 연결 ($LINK)"
    start_routers
    say "2/3 안전 설정값 확인·적용 (바뀌는 값이 있으면 y 입력)"
    if [ "$LINK" = "sitl" ]; then python3 set_params.py --drones "$DRONES" --apply < <(echo y); else python3 set_params.py --drones "$DRONES" --apply; fi
    say "3/3 미션 만들기 (기체가 놓인 위치·기수 방향 기준)"
    python3 plan_gen.py --profile "$SITE" --drones "$DRONES" --from-vehicles --bearing "$BEARING"
    say "준비 완료. 다음: ./demo.sh fly"
    ;;
  fly)
    say "현장: $SITE / 기체: $DRONES"
    start_routers
    say "지도 화면 실행"
    python3 guard_map.py > /tmp/guard_map.log 2>&1 &
    sleep 1
    if [ "$DRONES" = "D1,D2" ]; then SC=S7_duo; else SC=S0_integrated; fi
    echo
    echo "  가드가 켜지면 이렇게 입력하세요:"
    echo "    1) load $SC rehearsal   →  start      (첫 비행: 리허설)"
    echo "    2) load $SC demo        →  start      (본 시연)"
    echo "    비상: h   /  상태: s  /  끝: q"
    say "가드 실행"
    python3 guard.py --drones "$DRONES"
    ;;
  stop)
    say "연결 프로그램·지도 화면 종료"
    pkill -f mavlink-routerd || true
    pkill -f guard_map.py || true
    echo "  완료"
    ;;
  *)
    sed -n '3,12p' "$0"
    ;;
esac
