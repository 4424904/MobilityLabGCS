#!/usr/bin/env bash
# ACACT Guard 설치 스크립트 (Ubuntu 22.04 / 24.04)
# 사용: cd ~/acact_guard && bash install.sh
# 인터넷 연결 필요. 중간에 sudo 비밀번호를 물어봅니다. 약 5~10분.
set -e
cd "$(dirname "$0")"
step(){ echo; echo "==== $1 ===="; }

step "1/5 기본 도구 설치"
sudo apt update
sudo apt install -y python3-pip python3-venv python3-tk git unzip screen meson ninja-build pkg-config gcc g++
# QGroundControl(AppImage) 실행에 필요
sudo apt install -y libfuse2 2>/dev/null || sudo apt install -y libfuse2t64 || true

step "2/5 모뎀(USB) 접근 권한"
sudo usermod -a -G dialout "$USER"
sudo apt remove -y modemmanager || true

step "3/5 파이썬 가상환경 (~/acact-venv)"
python3 -m venv ~/acact-venv
~/acact-venv/bin/pip install --upgrade pip
~/acact-venv/bin/pip install "mavsdk<4" numpy matplotlib

step "4/5 mavlink-router 빌드"
if command -v mavlink-routerd >/dev/null 2>&1; then
  echo "이미 설치됨: $(command -v mavlink-routerd)"
else
  rm -rf /tmp/mavlink-router
  git clone https://github.com/mavlink-router/mavlink-router.git /tmp/mavlink-router
  (cd /tmp/mavlink-router && git submodule update --init --recursive && meson setup build . && ninja -C build && sudo ninja -C build install)
fi

step "5/5 설치 확인 (시뮬레이션 1회)"
chmod +x launch_sitl.sh
~/acact-venv/bin/python sim_check.py S0_integrated --seeds 1 | tail -3

echo
echo "설치 완료."
echo " - 로그아웃 후 다시 로그인해야 모뎀 권한이 적용됩니다."
echo " - 터미널을 새로 열 때마다:  source ~/acact-venv/bin/activate"
echo " - QGroundControl 은 공식 사이트에서 AppImage 를 받아 실행하세요 (가이드 2장)."
