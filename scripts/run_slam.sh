#!/usr/bin/env bash
# One entry point for SLAM on the Pi5 and on the PC/WSL.
#
#   bash scripts/run_slam.sh map            new map (the previous database is backed up first)
#   bash scripts/run_slam.sh extend         keep mapping into the existing database (new session)
#   bash scripts/run_slam.sh loc            localize in the existing map, no new map data
#   bash scripts/run_slam.sh bag <bag_dir>  map from a ROS 2 bag recorded with record_bag.sh
#
# Any extra arguments are passed to ros2 launch, e.g.:
#   bash scripts/run_slam.sh map profile:=848,480,15 viz:=true
#
# On a Raspberry Pi the Pi5 tuning (config/rtabmap_pi5.yaml), 640x480@15 and viz:=false are applied.
set -eo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_DIR}/scripts/ros_env.sh"

MODE="${1:-}"
shift || true

DB="${SLAM_DB:-$HOME/.ros/rtabmap.db}"
MAPS_DIR="${HOME}/slam_data/maps"
mkdir -p "$(dirname "$DB")" "$MAPS_DIR"

if grep -qs "Raspberry Pi" /proc/device-tree/model; then
  DEFAULTS=(config:="${REPO_DIR}/config/rtabmap_pi5.yaml" profile:=640,480,15 viz:=false)
else
  DEFAULTS=(profile:=640,480,30 viz:=true)
fi

LAUNCH=(ros2 launch "${REPO_DIR}/launch/d435i_slam.launch.py" database_path:="$DB" "${DEFAULTS[@]}")

case "$MODE" in
  map)
    if [ -f "$DB" ]; then
      BACKUP="${MAPS_DIR}/rtabmap_$(date +%Y%m%d_%H%M%S).db"
      mv "$DB" "$BACKUP"
      echo "Previous map backed up to $BACKUP"
    fi
    exec "${LAUNCH[@]}" delete_db:=true "$@"
    ;;
  extend)
    exec "${LAUNCH[@]}" delete_db:=false "$@"
    ;;
  loc)
    if [ ! -f "$DB" ]; then
      echo "No map at $DB. Build one first: bash scripts/run_slam.sh map" >&2
      exit 1
    fi
    exec "${LAUNCH[@]}" localization:=true "$@"
    ;;
  bag)
    BAG="${1:-}"
    if [ -z "$BAG" ] || [ ! -d "$BAG" ]; then
      echo "Usage: bash scripts/run_slam.sh bag <bag_dir>" >&2
      exit 1
    fi
    shift
    [ -f "$DB" ] && mv "$DB" "${MAPS_DIR}/rtabmap_$(date +%Y%m%d_%H%M%S).db"
    "${LAUNCH[@]}" source:=ros2bag delete_db:=true "$@" &
    LAUNCH_PID=$!
    trap 'kill -TERM $LAUNCH_PID 2>/dev/null; wait $LAUNCH_PID' EXIT
    sleep 5   # let the SLAM nodes start before the data arrives
    ros2 bag play "$BAG" --clock
    echo "Bag finished. Press Ctrl+C to stop SLAM and save the map."
    wait $LAUNCH_PID
    ;;
  *)
    sed -n '2,12p' "$0"
    exit 1
    ;;
esac
