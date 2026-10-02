#!/usr/bin/env bash
# Archive the current map: database copy + 3D point cloud (.ply) + 2D grid for Nav2 (.pgm/.yaml).
#   bash scripts/export_map.sh [database.db]
# The 2D grid is only saved while SLAM is running (it is read from the /map topic).
set -eo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_DIR}/scripts/ros_env.sh"

DB="${1:-${SLAM_DB:-$HOME/.ros/rtabmap.db}}"
OUT="${HOME}/slam_data/maps/$(date +%Y%m%d_%H%M%S)"
[ -f "$DB" ] || { echo "No database at $DB" >&2; exit 1; }
mkdir -p "$OUT"

cp "$DB" "$OUT/rtabmap.db"
echo "Database -> $OUT/rtabmap.db"

if command -v rtabmap-export >/dev/null; then
  rtabmap-export --cloud --output map3d --output_dir "$OUT" "$OUT/rtabmap.db" \
    && echo "3D cloud -> $OUT/map3d*.ply"
else
  echo "rtabmap-export not found, skipped the 3D cloud (open the .db in rtabmap-databaseViewer on the PC)."
fi

if ros2 topic list 2>/dev/null | grep -qx /map; then
  timeout 30 ros2 run nav2_map_server map_saver_cli -f "$OUT/map2d" \
    && echo "2D grid -> $OUT/map2d.pgm/.yaml" || echo "2D grid save failed."
else
  echo "/map not published (SLAM not running), skipped the 2D grid."
fi
