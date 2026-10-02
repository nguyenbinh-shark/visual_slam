#!/usr/bin/env bash
# Laptop/WSL: watch the map that the Pi5 is building (same Wi-Fi/LAN, same ROS_DOMAIN_ID).
#   bash scripts/view_map.sh
set -eo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_DIR}/scripts/ros_env.sh"

echo "ROS_DOMAIN_ID=${ROS_DOMAIN_ID}. Looking for the Pi5 nodes..."
if ! timeout 10 ros2 node list 2>/dev/null | grep -q rtabmap; then
  echo "WARN: no rtabmap node seen yet. Check: SLAM running on the Pi, same ROS_DOMAIN_ID," \
       "WSL mirrored networking (setup_wsl_network.ps1), or set ROS_STATIC_PEERS in scripts/ros_env.sh."
fi

exec rviz2 -d "${REPO_DIR}/rviz/slam_view.rviz"
