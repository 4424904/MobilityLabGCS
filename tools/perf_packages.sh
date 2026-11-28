#!/usr/bin/env bash
# runtime packages for tools/perf_run.py on a GitHub ubuntu-24.04 runner
set -e
sudo apt-get -o Acquire::Retries=3 update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=3 install -y -qq --no-install-recommends \
  xvfb xauth xdotool libegl1 libgl1 libgl1-mesa-dri libglx-mesa0 \
  libxkbcommon-x11-0 libxcb-cursor0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-render-util0 \
  libxcb-xinerama0 libxcb-xkb1 libfontconfig1 libpulse0 libspeechd2 libasound2t64
nproc; free -m; lscpu | grep 'Model name' || true
