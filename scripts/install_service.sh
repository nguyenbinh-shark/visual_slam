#!/usr/bin/env bash
# Optional: start SLAM automatically at boot (systemd).
#   bash scripts/install_service.sh [extend|loc]   (default: extend; "map" is refused, it would reset the map every boot)
# Manage it with:
#   sudo systemctl status visual-slam      journalctl -u visual-slam -f
#   sudo systemctl stop visual-slam        sudo systemctl disable visual-slam
# Change the mode later in /etc/default/visual-slam, then: sudo systemctl restart visual-slam
set -eo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-extend}"
case "$MODE" in
  extend|loc) ;;
  *) echo "Mode must be extend or loc" >&2; exit 1 ;;
esac

sudo tee /etc/default/visual-slam >/dev/null <<EOF
# Mode passed to scripts/run_slam.sh: extend | loc
SLAM_MODE=${MODE}
# Extra ros2 launch arguments, e.g. SLAM_ARGS="profile:=848,480,15"
SLAM_ARGS=""
EOF

sudo tee /etc/systemd/system/visual-slam.service >/dev/null <<EOF
[Unit]
Description=RTAB-Map visual SLAM (RealSense D435i)
After=network-online.target
Wants=network-online.target

[Service]
User=${USER}
WorkingDirectory=${REPO_DIR}
EnvironmentFile=/etc/default/visual-slam
ExecStart=/bin/bash -c 'exec ${REPO_DIR}/scripts/run_slam.sh \$SLAM_MODE \$SLAM_ARGS'
# SIGINT lets RTAB-Map close and save its database cleanly.
KillSignal=SIGINT
TimeoutStopSec=30
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now visual-slam
echo "visual-slam service enabled (mode: ${MODE}). Logs: journalctl -u visual-slam -f"
