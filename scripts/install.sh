#!/usr/bin/env bash
# Install everything needed to run SLAM on Ubuntu 24.04: Raspberry Pi 5 (arm64) or PC/WSL (amd64).
# Pi-only steps (USB current) are skipped on a PC; the GUI tools are installed only on a PC.
#
#   git clone <repo> ~/visual_slam && cd ~/visual_slam && bash scripts/install.sh
set -eo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEED_REBOOT=0
IS_PI=0
grep -qs "Raspberry Pi" /proc/device-tree/model && IS_PI=1

step() { echo -e "\n==== $* ===="; }

. /etc/os-release
if [ "$VERSION_CODENAME" != "noble" ]; then
  echo "This needs Ubuntu 24.04 (noble), found: $PRETTY_NAME" >&2
  exit 1
fi

step "Base packages and locale"
sudo apt update
sudo apt install -y locales software-properties-common curl git usbutils unzip
sudo locale-gen en_US en_US.UTF-8
sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
sudo add-apt-repository -y universe

step "ROS 2 apt repository"
if dpkg -s ros2-apt-source >/dev/null 2>&1 || ls /etc/apt/sources.list.d/ros2* >/dev/null 2>&1; then
  echo "Already configured."
else
  ROS_APT_SOURCE_VERSION=$(curl -s https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest \
    | grep -F '"tag_name"' | awk -F'"' '{print $4}')
  curl -L -o /tmp/ros2-apt-source.deb \
    "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_SOURCE_VERSION}/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.noble_all.deb"
  sudo dpkg -i /tmp/ros2-apt-source.deb
fi

step "ROS 2 Jazzy + SLAM packages"
sudo apt update
PKGS=(
  ros-jazzy-ros-base
  ros-jazzy-realsense2-camera
  ros-jazzy-rtabmap-slam
  ros-jazzy-rtabmap-odom
  ros-jazzy-rtabmap-util
  ros-jazzy-imu-filter-madgwick
  ros-jazzy-robot-localization
  ros-jazzy-nav2-map-server
  ros-jazzy-rosbag2-storage-mcap
)
# The GUI (rtabmap_viz) is only useful on a machine with a screen.
[ "$IS_PI" = 0 ] && PKGS+=(ros-jazzy-rtabmap-viz ros-jazzy-rviz2)
sudo apt install -y "${PKGS[@]}"

step "RealSense udev rule"
sudo curl -sSL -o /etc/udev/rules.d/99-realsense-libusb.rules \
  https://raw.githubusercontent.com/IntelRealSense/librealsense/master/config/99-realsense-libusb.rules
sudo udevadm control --reload-rules
sudo udevadm trigger

if [ "$IS_PI" = 1 ]; then
  step "Pi5: allow full USB current for the D435i"
  CFG=/boot/firmware/config.txt
  if [ -f "$CFG" ] && ! grep -q '^usb_max_current_enable=1' "$CFG"; then
    sudo cp "$CFG" "${CFG}.bak.$(date +%Y%m%d_%H%M%S)"
    printf '\n[all]\nusb_max_current_enable=1\n' | sudo tee -a "$CFG" >/dev/null
    NEED_REBOOT=1
    echo "Added usb_max_current_enable=1 to $CFG"
  else
    echo "Already set."
  fi
fi

step "Shell environment"
LINE="source ${REPO_DIR}/scripts/ros_env.sh"
grep -qxF "$LINE" ~/.bashrc || echo "$LINE" >> ~/.bashrc
mkdir -p ~/slam_data/maps
chmod +x "${REPO_DIR}"/scripts/*.sh

step "Done"
if [ "$NEED_REBOOT" = 1 ]; then
  echo "Reboot now (sudo reboot), then run: bash scripts/check_camera.sh"
else
  echo "Open a new shell, then run: bash scripts/check_camera.sh"
fi
