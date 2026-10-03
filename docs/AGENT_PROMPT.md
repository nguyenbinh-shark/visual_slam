# Prompt cho AI agent: robot tuần tra dựng map 3D và gửi về máy chủ

> Dán toàn bộ nội dung dưới đây cho AI agent (Claude Code hoặc tương đương) chạy trên Raspberry Pi 5, trong thư mục repo `~/visual_slam`.

---

## Vai trò và mục tiêu

Bạn là kỹ sư robotics làm việc trực tiếp trên Raspberry Pi 5 của tôi. Bạn có quyền chạy lệnh và sửa file trong repo `~/visual_slam`.

Mục tiêu cuối cùng: robot di động tự đi tuần tra theo lộ trình trong tòa nhà. Mỗi lượt tuần tra, robot cập nhật map 3D bằng RTAB-Map. Hết lượt, robot export map rồi gửi về máy chủ. Khi mất mạng, map được giữ lại trên Pi và tự gửi khi có mạng trở lại.

Phạm vi chỉ gồm: SLAM/map, điều hướng tuần tra, đồng bộ map lên máy chủ. Không thêm module nhận diện người hay vật thể.

## Môi trường

- Raspberry Pi 5 8GB, Ubuntu Server 24.04 arm64, ROS 2 Jazzy (cài qua apt). Không có màn hình; tôi truy cập qua SSH.
- Camera Intel RealSense D435i (RGB-D + IMU), cắm cổng USB3.
- Máy chủ nhận map: **[ĐIỀN: IP/hostname, user, hệ điều hành của máy chủ]**.
- Đế robot: **[ĐIỀN: loại đế, cách điều khiển động cơ (UART/CAN/...), có encoder không, đường kính bánh, khoảng cách hai bánh, kích thước robot]**.
- Lidar 2D: **[ĐIỀN: có/không, model]**.

Nếu các mục [ĐIỀN] còn trống, hỏi tôi trước khi làm giai đoạn cần đến thông tin đó. Không tự đoán thông số phần cứng.

## Hiện trạng repo (đã có, đọc kỹ trước khi sửa)

Đọc `README.md` trước. Tóm tắt:

| File | Chức năng |
|---|---|
| `launch/d435i_slam.launch.py` | Pipeline: realsense2_camera → imu_filter_madgwick → rtabmap_odom/rgbd_odometry → rtabmap_slam/rtabmap (+ rtabmap_viz khi `viz:=true`). Args: `source` (camera/rsbag/ros2bag), `image` (infra/color), `profile`, `imu`, `config`, `frame_id`, `database_path`, `delete_db`, `localization`, `viz`. Dùng `OpaqueFunction`. |
| `config/rtabmap_pi5.yaml` | Tham số RTAB-Map cho Pi5 (giá trị là string, key `/**`). Có dòng `Reg/Force3DoF` đang comment. |
| `scripts/install.sh` | Cài ROS Jazzy ros-base + gói SLAM, udev rule RealSense, `usb_max_current_enable=1`, thêm `source scripts/ros_env.sh` vào `~/.bashrc`. Tự nhận biết Pi hay PC. |
| `scripts/ros_env.sh` | Source ROS, `ROS_DOMAIN_ID=42`, gợi ý `ROS_STATIC_PEERS`. |
| `scripts/run_slam.sh` | Chế độ `map` (backup DB cũ rồi map mới), `extend`, `loc`, `bag <dir>`. Trên Pi tự thêm `config:=config/rtabmap_pi5.yaml profile:=640,480,15 viz:=false`. |
| `scripts/check_camera.sh` | Kiểm tra tốc độ USB và Hz các stream. |
| `scripts/export_map.sh` | Copy DB, `rtabmap-export --cloud` ra `.ply`, `map_saver_cli` ra `.pgm/.yaml`, vào `~/slam_data/maps/<timestamp>/`. |
| `scripts/install_service.sh` | systemd service `visual-slam` (mode extend/loc, `KillSignal=SIGINT`). |
| `scripts/record_bag.sh`, `scripts/view_map.sh`, `rviz/slam_view.rviz` | Ghi bag; xem map từ laptop. |

Sự thật kỹ thuật đã xác minh (đừng đổi nếu không có lý do):
- Camera chạy với `camera_namespace:=''`, nên topic có dạng `/camera/infra1/image_rect_raw`, `/camera/depth/image_rect_raw`, `/camera/imu`. IMU sau filter là `/imu/data`.
- Các node rtabmap không có namespace: `/odom` (visual odometry), `/map` (OccupancyGrid, QoS reliable + transient local), `/cloud_map`, `/mapData`. TF: `map → odom → camera_link`.
- DB mặc định: `~/.ros/rtabmap.db`.
- Gói có trên apt arm64 noble: `ros-jazzy-navigation2`, `ros-jazzy-nav2-bringup`, `ros-jazzy-nav2-simple-commander`, `ros-jazzy-twist-mux`, `ros-jazzy-teleop-twist-keyboard`, `ros-jazzy-rplidar-ros`, `ros-jazzy-depthimage-to-laserscan`, `ros-jazzy-pointcloud-to-laserscan`. `explore_lite` (m-explore) **không** có trên apt.

Chưa từng chạy end-to-end trên phần cứng thật. File `rviz/slam_view.rviz` chưa được mở thử. Nếu gặp lỗi trong file có sẵn, sửa tận gốc và ghi lại.

## Quy tắc làm việc

1. Làm **theo từng giai đoạn bên dưới, đúng thứ tự**. Xong mỗi giai đoạn: chạy kiểm tra nghiệm thu, báo kết quả thật (kèm số liệu/log ngắn), commit với message rõ ràng, rồi dừng chờ tôi xác nhận trước khi sang giai đoạn sau.
2. Ưu tiên gói apt. Chỉ build từ source khi thật sự cần, và hỏi tôi trước.
3. Giữ kiểu code hiện có: script bash dùng `set -eo pipefail` (không dùng `-u` vì setup.bash của ROS lỗi với `-u`); `REPO_DIR` tính từ vị trí script; source `scripts/ros_env.sh`; comment tiếng Anh; README tiếng Việt.
4. Ưu tiên chạy được trực tiếp từ repo không cần `colcon build` (launch file theo đường dẫn, node Python là script `rclpy` độc lập). Nếu bắt buộc phải có package ROS, tạo workspace `~/visual_slam/ros_ws` và script build.
5. Không commit map, bag, log, mật khẩu, private key (đã có `.gitignore`; thêm mục mới nếu cần). Thông tin máy chủ để trong file cấu hình không commit (ví dụ `config/sync.env`, kèm `config/sync.env.example` được commit).
6. Mọi thay đổi `sudo` lên hệ thống (systemd, `/etc`, `/boot/firmware`) phải nằm trong script có thể chạy lại nhiều lần mà không hỏng (idempotent), và có backup file trước khi sửa.
7. Cập nhật `README.md` cho mọi tính năng mới: cách chạy, cách kiểm tra, sự cố thường gặp.
8. Không báo "xong" nếu chưa chạy thử. Nếu không thể test (thiếu phần cứng), nói rõ phần nào chưa test.

---

## Giai đoạn 0: Xác nhận nền tảng SLAM trên Pi5

1. Chạy `bash scripts/install.sh`, reboot nếu được yêu cầu.
2. `bash scripts/check_camera.sh`: cần USB 5000 Mbps, ảnh khoảng 15 Hz, IMU khoảng 200 Hz.
3. `bash scripts/run_slam.sh map`, tôi cầm camera đi quanh phòng 2–3 phút. Trong lúc đó đo `ros2 topic hz /odom`, nhiệt độ CPU, `htop`.
4. `bash scripts/export_map.sh` khi SLAM đang chạy, kiểm tra đủ `rtabmap.db`, `.ply`, `.pgm/.yaml`.

**Nghiệm thu:** `/odom` ≥ 10 Hz, CPU < 80 °C, export đủ 3 loại file. Nếu không đạt, chỉnh `config/rtabmap_pi5.yaml` hoặc `profile` và báo lại số liệu trước và sau.

## Giai đoạn 1: Đồng bộ map lên máy chủ (store-and-forward)

Tạo:
- `config/sync.env.example` (commit) và `config/sync.env` (không commit): `SERVER_HOST`, `SERVER_USER`, `SERVER_DIR` (mặc định `~/robot_maps`), `ROBOT_ID` (mặc định hostname), `SSH_KEY` (mặc định `~/.ssh/robot_sync`).
- `scripts/setup_sync.sh` (chạy trên Pi): tạo SSH key riêng không passphrase nếu chưa có, hướng dẫn hoặc thực hiện `ssh-copy-id`, kiểm tra kết nối.
- `scripts/setup_server.sh` (chạy trên máy chủ Linux/WSL): tạo `SERVER_DIR`, cài `rsync`, in hướng dẫn cài `rtabmap` để xem map.
- `scripts/sync_maps.sh`: với mỗi thư mục trong `~/slam_data/maps/` **đã hoàn tất** và chưa gửi, `rsync -az --partial` tới `SERVER_USER@SERVER_HOST:SERVER_DIR/ROBOT_ID/<tên thư mục>/`. Gửi thành công thì tạo file đánh dấu `.synced`. Mất mạng thì thoát êm (exit 0, log cảnh báo) để lần sau thử lại. Dùng `flock` để không chạy chồng.
- Sửa `scripts/export_map.sh` để export **nguyên tử**: ghi vào `<dir>.tmp`, xong hết mới `mv` thành `<dir>` và tạo `.complete`. `sync_maps.sh` chỉ gửi thư mục có `.complete`.
- systemd timer `visual-slam-sync.timer` (mỗi 2 phút) + service tương ứng, cài bằng `scripts/install_sync_service.sh`.
- Tuỳ chọn: giữ tối đa N bản map đã sync trên Pi (`KEEP_SYNCED=10`), xoá bản cũ nhất **chỉ khi** đã có `.synced`.

**Nghiệm thu:**
- Export map, map xuất hiện trên máy chủ trong vòng 2 phút.
- Rút mạng hoặc tắt máy chủ, export thêm 2 bản, map nằm chờ trên Pi. Cắm lại mạng, cả 2 bản tự gửi lên, không bị trùng, không gửi bản dở dang.
- Mở được `rtabmap.db` trên máy chủ bằng `rtabmap-databaseViewer` và file `.ply` bằng CloudCompare.

## Giai đoạn 2: Tích hợp đế robot

Cần thông tin đế robot (hỏi tôi nếu còn thiếu).

1. **Driver đế:** nhận `/cmd_vel` (`geometry_msgs/Twist`, hoặc `TwistStamped` nếu Nav2 Jazzy cấu hình như vậy; kiểm tra và thống nhất), publish `/wheel/odom` (`nav_msgs/Odometry`) từ encoder, **không** publish TF `odom → base_link` (để EKF làm). Nếu đế có driver ROS 2 sẵn thì dùng; nếu tự làm (STM32/UART hoặc CAN) thì viết node `rclpy` trong `nodes/base_driver.py`, giao thức đọc từ tài liệu tôi cung cấp. Có watchdog: không nhận `/cmd_vel` quá 0.5 s thì dừng động cơ.
2. **TF tĩnh:** `base_link → camera_link` theo vị trí lắp camera đo thực tế (x, y, z, roll, pitch, yaw), để trong `config/robot.yaml`. Nếu có lidar thì thêm `base_link → laser`.
3. **EKF (`robot_localization`):** fuse `/wheel/odom` (vx, vyaw) + `/imu/data` (vyaw, có thể cả yaw), `two_d_mode: true`, publish `odom → base_link` và `/odometry/filtered`. Config: `config/ekf.yaml`.
4. **Sửa launch:** thêm arg `odom_source:=visual|external` vào `launch/d435i_slam.launch.py`.
   - `external`: không chạy `rgbd_odometry`; rtabmap remap `odom → /odometry/filtered`, `subscribe_odom_info: false`, `frame_id: base_link`.
   - Bật `Reg/Force3DoF: "true"` khi chạy trên robot.
   - Nếu có lidar: `subscribe_scan: true`, `Grid/Sensor` dùng lidar, `Reg/Strategy` cân nhắc ICP/visual+ICP.
   - Giữ nguyên hành vi cũ khi `odom_source:=visual` (mặc định) để vẫn test cầm tay được.
5. Tạo `launch/robot_bringup.launch.py` gồm: driver đế + TF tĩnh + EKF + lidar (nếu có) + SLAM (`odom_source:=external`). `run_slam.sh` thêm cờ hoặc chế độ để dùng bringup này.
6. Teleop: `teleop_twist_keyboard` qua `twist_mux` (ưu tiên: teleop > nav). Thêm topic e-stop có ưu tiên cao nhất.

**Nghiệm thu:**
- Đẩy robot đi thẳng 2 m bằng teleop: `/odometry/filtered` báo khoảng 2 m (sai số < 5%).
- Quay tại chỗ 360°: yaw khoảng 360° (sai số < 5°).
- Lái tay đi một vòng tầng nhà, map 2D khép vòng không bị nhân đôi tường. Export và sync về máy chủ thành công.

## Giai đoạn 3: Tuần tra tự động bằng Nav2

1. Cài `ros-jazzy-navigation2 ros-jazzy-nav2-bringup ros-jazzy-nav2-simple-commander` (thêm vào `install.sh`).
2. Dùng `nav2_bringup/navigation_launch.py` (không dùng AMCL/map_server: RTAB-Map đã cung cấp `/map` và TF `map → odom`). Config `config/nav2_params.yaml`:
   - footprint theo kích thước robot thật;
   - tốc độ tối đa 0.3 m/s, quay 0.8 rad/s (khởi đầu an toàn);
   - costmap: obstacle layer từ lidar (nếu có) và/hoặc depth D435i (`/camera/depth/...` → pointcloud, hoặc `/cloud_obstacles` của rtabmap); inflation theo bán kính robot;
   - controller (MPPI hoặc RPP) và planner (NavFn/Smac2D) phù hợp robot vi sai.
3. Waypoint: `config/patrol_waypoints.yaml` (danh sách x, y, yaw trong frame `map`). Script `scripts/record_waypoint.sh` hoặc node nhỏ để lưu vị trí hiện tại của robot thành waypoint khi tôi lái tay tới đó.
4. Node `nodes/patrol.py` (`rclpy` + `nav2_simple_commander.BasicNavigator`):
   - lặp: đi qua toàn bộ waypoint, mỗi waypoint dừng và quay 360° chậm để map đủ góc nhìn;
   - waypoint thất bại (bị chặn/timeout): thử lại 1 lần, rồi bỏ qua, ghi log;
   - hết mỗi lượt: gọi `export_map.sh` (SLAM vẫn chạy), `sync_maps.sh` sẽ tự gửi;
   - tham số: số lượt (`0` = vô hạn), thời gian nghỉ giữa lượt, quay về điểm xuất phát khi kết thúc;
   - dừng an toàn khi: nhận e-stop, mất localization (TF `map → base_link` không cập nhật quá 2 s), pin yếu (nếu đế có báo pin).
5. `run_slam.sh patrol` hoặc `scripts/run_patrol.sh`: bringup robot + SLAM chế độ `extend` + Nav2 + patrol node. Có service systemd tuỳ chọn.

**Nghiệm thu:**
- 3 lượt tuần tra liên tiếp không cần can thiệp, robot không va chạm.
- Sau mỗi lượt có một thư mục map mới trên máy chủ.
- Báo cáo: thời gian mỗi lượt, số waypoint đạt/thất bại, `/odom` Hz, CPU/nhiệt độ trong lúc chạy.

## Giai đoạn 4 (tuỳ chọn, hỏi trước): Tự khám phá lần đầu

Nếu tôi muốn robot tự đi dựng map lần đầu thay vì lái tay: dùng frontier exploration (`m-explore-ros2`/`explore_lite`, build từ source trong `ros_ws`). Giới hạn vùng khám phá, tốc độ thấp, có e-stop. Khám phá xong thì lưu map và chuyển sang tuần tra theo waypoint.

---

## Cách báo cáo sau mỗi giai đoạn

- Đã làm gì (file mới/sửa, một dòng mỗi file).
- Kết quả nghiệm thu: đạt/không đạt, kèm số liệu thật.
- Phần chưa test được và lý do.
- Vấn đề còn tồn tại và đề xuất.
- Commit hash.
