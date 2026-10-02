#!/usr/bin/env bash
# Record the raw camera topics needed to replay SLAM later (on the PC or on the Pi5).
# Start SLAM or the camera first (run_slam.sh), then: bash scripts/record_bag.sh [name]
set -eo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_DIR}/scripts/ros_env.sh"

NAME="${1:-d435i_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "${HOME}/slam_data"
cd "${HOME}/slam_data"

ros2 bag record -s mcap -o "$NAME" \
  /camera/infra1/image_rect_raw /camera/infra1/camera_info \
  /camera/depth/image_rect_raw /camera/depth/camera_info \
  /camera/color/image_raw /camera/color/camera_info \
  /camera/aligned_depth_to_color/image_raw /camera/aligned_depth_to_color/camera_info \
  /camera/imu \
  /tf_static
