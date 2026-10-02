#!/usr/bin/env bash
# Download Intel's official D435i sample recording (~470 MB, includes IMU) for testing without a camera.
set -euo pipefail

DIR="${HOME}/slam_data"
mkdir -p "$DIR"
cd "$DIR"

if [ ! -f d435i_sample_data.zip ]; then
  curl -L -o d435i_sample_data.zip \
    https://librealsense.realsenseai.com/rs-tests/TestData/d435i_sample_data.zip
fi
unzip -n d435i_sample_data.zip

echo "Recordings in $DIR:"
find "$DIR" -name "*.bag" -exec ls -lh {} \;
