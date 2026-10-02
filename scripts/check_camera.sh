#!/usr/bin/env bash
# Check the D435i: USB connection speed, then stream rates through ROS 2 (~25 s).
set -eo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_DIR}/scripts/ros_env.sh"

echo "== USB =="
DEV=""
for d in /sys/bus/usb/devices/*; do
  if [ "$(cat "$d/idVendor" 2>/dev/null)" = "8086" ] && [ "$(cat "$d/idProduct" 2>/dev/null)" = "0b3a" ]; then
    DEV="$d"
    break
  fi
done
if [ -z "$DEV" ]; then
  echo "FAIL: D435i (8086:0b3a) not found. Check the cable (WSL: run attach_d435i.ps1)."
  exit 1
fi
SPEED=$(cat "$DEV/speed")
echo "D435i at $DEV, speed ${SPEED} Mbps"
if [ "$SPEED" -lt 5000 ]; then
  echo "WARN: USB2 link. Use a USB3 port (blue) and a USB3 cable, or depth/IMU will be limited."
fi

echo "== Streams (starting camera driver) =="
ros2 launch realsense2_camera rs_launch.py \
  enable_infra1:=true enable_depth:=true enable_color:=false \
  enable_gyro:=true enable_accel:=true unite_imu_method:=2 enable_sync:=true \
  depth_module.depth_profile:=640,480,15 depth_module.infra_profile:=640,480,15 \
  >/tmp/check_camera.log 2>&1 &
CAM_PID=$!
trap 'kill -TERM $CAM_PID 2>/dev/null; wait $CAM_PID 2>/dev/null' EXIT
sleep 10

# rs_launch.py default namespace: /camera/camera/...
for t in /camera/camera/infra1/image_rect_raw /camera/camera/depth/image_rect_raw /camera/camera/imu; do
  RATE=$(timeout 6 ros2 topic hz "$t" 2>/dev/null | grep 'average rate' | tail -1 || true)
  echo "$t: ${RATE:-NO DATA}"
done
echo "Expected: images ~15 Hz, imu ~200 Hz. Driver log: /tmp/check_camera.log"
