#!/usr/bin/env bash
# ACACT Guard 에이전트를 로그인할 때 자동으로 켜지게 등록 (systemd 사용자 서비스)
#   bash install_agent.sh            # 같은 PC 의 MobilityLab GCS 만
#   bash install_agent.sh --allow-lan  # 같은 망의 다른 PC(Windows GCS)에서도 명령 허용 (시험용)
# 해제: systemctl --user disable --now acact-guard-agent
set -e
cd "$(dirname "$0")"
DIR="$(pwd)"
PY="$HOME/acact-venv/bin/python"; [ -x "$PY" ] || PY="$(command -v python3)"
mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/acact-guard-agent.service" <<UNIT
[Unit]
Description=ACACT Guard agent (MobilityLab GCS)

[Service]
WorkingDirectory=$DIR
ExecStart=$PY -u $DIR/guard_agent.py $*
Restart=on-failure
RestartSec=3
KillSignal=SIGINT
TimeoutStopSec=20

[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
systemctl --user enable --now acact-guard-agent
echo "등록 완료. 상태: systemctl --user status acact-guard-agent / 로그: journalctl --user -u acact-guard-agent -f"
