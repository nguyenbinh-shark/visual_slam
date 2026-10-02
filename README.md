# Visual SLAM: Raspberry Pi 5 + RealSense D435i + ROS 2 Jazzy

Dựng map 3D bằng RTAB-Map (RGB-D + IMU) với camera D435i.

Cùng một repo chạy được trên hai môi trường:
- **PC/WSL**: test, xem map, tinh chỉnh tham số.
- **Pi5 8GB, Ubuntu 24.04**: clone về, cài, chạy.

```
launch/d435i_slam.launch.py   pipeline: camera/bag -> imu_filter -> rgbd_odometry -> rtabmap (+ rtabmap_viz)
config/rtabmap_pi5.yaml       tham số RTAB-Map chỉnh cho CPU Pi5 (tự áp dụng trên Pi)
rviz/slam_view.rviz           cấu hình rviz2 để xem map từ laptop
scripts/
  install.sh                  cài toàn bộ (Pi5 hoặc PC/WSL, tự nhận biết)
  check_camera.sh             kiểm tra USB3 + tần số stream của D435i
  run_slam.sh                 chạy SLAM: map | extend | loc | bag
  record_bag.sh               ghi dữ liệu camera để replay
  export_map.sh               lưu map: .db + point cloud 3D (.ply) + grid 2D (.pgm/.yaml)
  install_service.sh          (tuỳ chọn) tự chạy SLAM khi Pi5 khởi động
  view_map.sh                 laptop: mở rviz2 xem map Pi5 đang dựng
  ros_env.sh                  môi trường ROS chung (ROS_DOMAIN_ID=42)
  get_sample_data.sh          tải bản ghi mẫu D435i của Intel (test không cần camera)
  attach_d435i.ps1            Windows: chia sẻ D435i vào WSL (usbipd)
  setup_wsl_network.ps1       Windows: cho WSL thấy Pi5 trong mạng LAN
```

---

## Phần A: Chuẩn bị (một lần)

### A1. Phần cứng Pi5

| Thứ | Ghi chú |
|---|---|
| Raspberry Pi 5 8GB | |
| Nguồn **5V 5A (27W)** chính hãng | Nguồn yếu thì D435i sẽ ngắt kết nối giữa chừng |
| Tản nhiệt chủ động (Active Cooler) | Không có tản thì CPU hạ xung, odometry tụt Hz |
| Thẻ microSD A2 ≥ 64GB **hoặc** SSD NVMe (HAT M.2) | SSD nên dùng nếu ghi bag (~14 MB/s) |
| Cáp USB3 (USB-C → USB-A) đi kèm D435i | Cắm vào cổng **USB3 màu xanh** của Pi5 |

### A2. Cài Ubuntu cho Pi5

1. Dùng **Raspberry Pi Imager**: chọn *Other general-purpose OS → Ubuntu → Ubuntu Server 24.04 LTS (64-bit)*.
2. Trong *Edit settings*, đặt hostname (ví dụ `slam-pi`), user/password, Wi-Fi và bật **SSH**.
3. Ghi thẻ, cắm vào Pi5, bật nguồn, rồi từ laptop chạy `ssh <user>@slam-pi.local`.
4. Cập nhật hệ thống:
   ```bash
   sudo apt update && sudo apt full-upgrade -y && sudo reboot
   ```

### A3. Đưa repo lên GitHub (làm trên máy tính)

```bash
cd P:/prj_2026.1/visual_slam
git init && git add . && git commit -m "Visual SLAM D435i setup" && git branch -M main
git remote add origin https://github.com/<ban>/visual_slam.git
git push -u origin main
```

`.gitattributes` đã ép line ending LF, nên script commit từ Windows vẫn chạy được trên Pi.

---

## Phần B: Chạy trên Pi5

### B1. Clone và cài (khoảng 15–30 phút)

```bash
git clone https://github.com/<ban>/visual_slam.git ~/visual_slam
cd ~/visual_slam
bash scripts/install.sh
sudo reboot        # chỉ cần nếu script báo đã sửa /boot/firmware/config.txt
```

`install.sh` làm các việc sau:
- Thêm repo apt của ROS 2.
- Cài ROS 2 Jazzy ros-base, realsense2_camera, rtabmap (slam/odom/util), imu_filter_madgwick, robot_localization, nav2_map_server.
- Cài udev rule cho D435i.
- Bật `usb_max_current_enable=1` để cổng USB cấp đủ dòng.
- Thêm `source scripts/ros_env.sh` vào `~/.bashrc`.

### B2. Kiểm tra camera

```bash
bash scripts/check_camera.sh
```

**Đạt khi:**
- `speed 5000 Mbps`. Nếu thấy 480 tức đang chạy USB2: đổi cổng hoặc cáp.
- Ảnh khoảng 15 Hz.
- IMU khoảng 200 Hz.

### B3. Dựng map

```bash
bash scripts/run_slam.sh map
```

- Trên Pi, script tự dùng `config/rtabmap_pi5.yaml`, profile 640x480@15 và tắt GUI.
- Đi chậm (dưới 0.5 m/s), quay chậm. Nên đi vòng lại chỗ cũ để RTAB-Map có loop closure.
- Dừng bằng **Ctrl+C** một lần, rồi chờ tiến trình thoát hẳn để database được lưu.
- Map nằm ở `~/.ros/rtabmap.db`. Lần `map` sau sẽ tự backup map cũ vào `~/slam_data/maps/`.

Các chế độ khác:

```bash
bash scripts/run_slam.sh extend                 # mapping tiếp vào map cũ (thêm khu vực mới)
bash scripts/run_slam.sh loc                    # chỉ định vị trong map đã có
bash scripts/run_slam.sh map profile:=848,480,15   # truyền thêm tham số launch tuỳ ý
```

### B4. Xem map trực tiếp từ laptop

Trên Windows, chạy **một lần** bằng PowerShell Admin:

```powershell
powershell -ExecutionPolicy Bypass -File P:\prj_2026.1\visual_slam\scripts\setup_wsl_network.ps1
```

Rồi trong WSL (cùng mạng Wi-Fi với Pi5):

```bash
cd /mnt/p/prj_2026.1/visual_slam
bash scripts/view_map.sh
```

rviz2 sẽ hiện grid 2D (`/map`), point cloud 3D (`/cloud_map`), TF và quỹ đạo `/odom`.

Nếu không thấy dữ liệu:
- Hai máy phải cùng `ROS_DOMAIN_ID` (mặc định 42).
- Router chặn multicast thì đặt `ROS_STATIC_PEERS` trong `scripts/ros_env.sh` (IP của máy bên kia) trên cả hai máy.

### B5. Lưu và xuất map

Trong lúc SLAM còn chạy, mở terminal khác:

```bash
bash scripts/export_map.sh
```

Kết quả nằm trong `~/slam_data/maps/<thời gian>/`:
- `rtabmap.db`: database đầy đủ.
- `map3d*.ply`: point cloud 3D, mở bằng CloudCompare/MeshLab.
- `map2d.pgm/.yaml`: grid 2D cho Nav2.

Chép về laptop:

```bash
scp -r <user>@slam-pi.local:~/slam_data/maps ./maps
```

Trên laptop, mở `rtabmap-databaseViewer rtabmap.db` để xem lại từng frame và các loop closure.

### B6. (Tuỳ chọn) Tự chạy khi bật nguồn

```bash
bash scripts/install_service.sh extend     # hoặc: loc
journalctl -u visual-slam -f               # xem log
sudo systemctl stop visual-slam            # dừng (lưu map an toàn)
sudo systemctl disable visual-slam         # tắt tự chạy
```

Service chỉ cho phép `extend`/`loc`. Không có `map` để tránh xoá map mỗi lần khởi động.

### B7. Ghi dữ liệu để tinh chỉnh trên PC

```bash
# terminal 1
bash scripts/run_slam.sh map
# terminal 2
bash scripts/record_bag.sh phong_lab
```

Copy `~/slam_data/phong_lab` về PC, rồi chạy lại nhiều lần với tham số khác nhau:

```bash
bash scripts/run_slam.sh bag ~/slam_data/phong_lab
```

---

## Phần C: Test trên PC/WSL (không cần Pi)

```bash
cd /mnt/p/prj_2026.1/visual_slam
bash scripts/install.sh                       # trên PC sẽ cài thêm rtabmap_viz + rviz2
```

**Không có camera** (dùng bản ghi mẫu Intel):

```bash
bash scripts/get_sample_data.sh
ros2 launch launch/d435i_slam.launch.py source:=rsbag image:=color bag:=$HOME/slam_data/<file>.bag
```

**Có camera:**
1. Cắm D435i vào USB3 của laptop.
2. Chạy `scripts\attach_d435i.ps1` bằng PowerShell Admin và để cửa sổ đó mở.
3. Trong WSL:
   ```bash
   bash scripts/check_camera.sh
   bash scripts/run_slam.sh map                  # mặc định trên PC: 640x480@30, có rtabmap_viz
   ```
4. Muốn mô phỏng đúng tải của Pi5:
   ```bash
   bash scripts/run_slam.sh map config:=$PWD/config/rtabmap_pi5.yaml profile:=640,480,15
   ```

---

## Tham số launch (`launch/d435i_slam.launch.py`)

| Tham số | Mặc định | Ý nghĩa |
|---|---|---|
| `source` | `camera` | `camera`, `rsbag` (file .bag Intel), `ros2bag` (`ros2 bag play --clock`) |
| `image` | `infra` | `infra`: infra1 + depth, tắt IR emitter (nhẹ nhất). `color`: color + depth đã align |
| `profile` | `640,480,30` | rộng, cao, FPS của camera (run_slam.sh trên Pi đặt 640,480,15) |
| `imu` | `true` | dùng IMU của D435i |
| `config` | rỗng | file YAML tham số RTAB-Map bổ sung |
| `frame_id` | `camera_link` | đổi thành `base_link` khi gắn lên robot (cần static TF base_link -> camera_link) |
| `localization` | `false` | `true`: chỉ định vị, không thêm map |
| `delete_db` | `true` | xoá database khi khởi động (run_slam.sh tự xử lý) |
| `viz` | `true` | bật rtabmap_viz |

## Mục tiêu hiệu năng trên Pi5

| Chỉ số | Cách đo | Mục tiêu |
|---|---|---|
| Tần số odometry | `ros2 topic hz /odom` | ≥ 10 Hz |
| Thời gian xử lý SLAM | log rtabmap, dòng `Processing time` | < 1 s (DetectionRate 1 Hz) |
| Nhiệt độ CPU | `cat /sys/class/thermal/thermal_zone0/temp` | < 80000 (80 °C) |
| CPU | `htop` | Không có lõi nào kẹt 100% liên tục |

Nếu odom dưới 10 Hz, chỉnh theo thứ tự:
1. Giảm `Vis/MaxFeatures` xuống 400 trong `config/rtabmap_pi5.yaml`.
2. Dùng `profile:=424,240,15`.
3. Thêm SSD và kiểm tra tản nhiệt.

## Sự cố thường gặp

| Hiện tượng | Cách xử lý |
|---|---|
| `No RealSense devices were found` | Cắm lại cổng USB3, kiểm tra nguồn 5A; WSL: kiểm tra cửa sổ `attach_d435i.ps1` |
| Camera tự ngắt giữa chừng | Nguồn yếu hoặc cáp kém; kiểm tra `usb_max_current_enable=1`; thử hub USB3 có nguồn |
| Kẹt ở "waiting imu" | `/camera/imu` không có dữ liệu: thử `unite_imu_method:=1`, hoặc `imu:=false` |
| Odometry lost (rtabmap_viz nền đỏ / log "lost") | Đi chậm hơn, thêm ánh sáng, tránh tường trơn; thử `image:=color` |
| Laptop không thấy topic của Pi | Cùng `ROS_DOMAIN_ID`, chạy `setup_wsl_network.ps1`, hoặc đặt `ROS_STATIC_PEERS` |
| Mạng Wi-Fi giật khi xem cloud | Tắt display "Map 3D" trong rviz, chỉ xem grid 2D; hoặc tắt Wi-Fi power save trên Pi: `sudo iw dev wlan0 set power_save off` |
