#!/usr/bin/env bash
# PX4 SITL(Gazebo) 4대 실행 (각각 새 터미널 탭)
# mavsdk_server 는 guard.py / plan_gen.py / set_params.py 가 자동으로 띄운다 (따로 실행하지 말 것).
# 사용: ./launch_sitl.sh   (PX4-Autopilot 경로가 다르면 PX4_DIR 지정)
PX4_DIR=${PX4_DIR:-$HOME/PX4-Autopilot}
# 이륙선: x 방향 15 m 간격
POSES=("0,0" "15,0" "30,0" "45,0")
for i in 1 2 3 4; do
  gnome-terminal --tab --title="PX4-$i" -- bash -c "cd $PX4_DIR; PX4_SYS_AUTOSTART=4001 PX4_SIM_MODEL=gz_x500 PX4_GZ_MODEL_POSE=\"${POSES[$((i-1))]}\" ./build/px4_sitl_default/bin/px4 -i $i; exec bash"
  sleep 6
done
echo "SITL 4대 실행. QGC 를 켜면 4대가 자동 연결됩니다."
echo "※ SITL 의 MAV_SYS_ID 는 인스턴스 번호+1 (2~5) 이라 가드 사전점검에서 SYS_ID 경고가 뜨는 것은 정상입니다."
