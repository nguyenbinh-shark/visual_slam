# RTAB-Map visual SLAM with a RealSense D435i (RGB-D + IMU), ROS 2 Jazzy.
# Based on rtabmap_examples/realsense_d435i_infra.launch.py, with switches for testing on a PC.
#
# Live camera (infra1 + depth, IR emitter off - lightest, same setup planned for the Pi5):
#   ros2 launch ./launch/d435i_slam.launch.py
# Live camera using color + aligned depth instead:
#   ros2 launch ./launch/d435i_slam.launch.py image:=color
# Intel .bag recording (librealsense playback, no camera needed):
#   ros2 launch ./launch/d435i_slam.launch.py source:=rsbag bag:=$HOME/slam_data/xxx.bag image:=color
# ROS 2 bag recorded with record_bag.sh (run `ros2 bag play <dir> --clock` in another shell):
#   ros2 launch ./launch/d435i_slam.launch.py source:=ros2bag
# Re-localize in a saved map instead of mapping:
#   ros2 launch ./launch/d435i_slam.launch.py localization:=true
# Extra RTAB-Map parameters from a YAML file (e.g. the Pi5 tuning):
#   ros2 launch ./launch/d435i_slam.launch.py config:=./config/rtabmap_pi5.yaml

import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, GroupAction, IncludeLaunchDescription, OpaqueFunction
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node, SetParameter


def launch_setup(context):
    def arg(name):
        return LaunchConfiguration(name).perform(context)

    source = arg('source')          # camera | rsbag | ros2bag
    image = arg('image')            # infra | color
    use_imu = arg('imu') == 'true'
    localization = arg('localization') == 'true'
    profile = arg('profile')        # e.g. 640,480,30
    db_path = os.path.expanduser(arg('database_path'))
    config = os.path.abspath(os.path.expanduser(arg('config'))) if arg('config') else ''

    if source not in ('camera', 'rsbag', 'ros2bag'):
        raise RuntimeError(f"source must be camera|rsbag|ros2bag, got '{source}'")
    if image not in ('infra', 'color'):
        raise RuntimeError(f"image must be infra|color, got '{image}'")

    actions = []

    if source == 'ros2bag':
        actions.append(SetParameter(name='use_sim_time', value=True))

    # --- Camera driver -------------------------------------------------------
    if source in ('camera', 'rsbag'):
        cam_args = {
            'camera_namespace': '',
            'camera_name': 'camera',
            'enable_depth': 'true',
            'enable_infra1': 'true' if image == 'infra' else 'false',
            'enable_infra2': 'false',
            'enable_color': 'true' if image == 'color' else 'false',
            'align_depth.enable': 'true' if image == 'color' else 'false',
            'enable_sync': 'true',
            'enable_gyro': 'true' if use_imu else 'false',
            'enable_accel': 'true' if use_imu else 'false',
            'unite_imu_method': arg('unite_imu_method'),
        }
        if source == 'camera':
            cam_args.update({
                'depth_module.depth_profile': profile,
                'depth_module.infra_profile': profile,
                'rgb_camera.color_profile': profile,
            })
        else:
            # Stream profiles come from the recording itself.
            cam_args['rosbag_filename'] = os.path.expanduser(arg('bag'))

        cam_group = []
        if source == 'camera' and image == 'infra':
            # The IR dot pattern adds fake features to the infra image: turn the emitter off.
            cam_group.append(SetParameter(name='depth_module.emitter_enabled', value=0))
        cam_group.append(IncludeLaunchDescription(
            PythonLaunchDescriptionSource(os.path.join(
                get_package_share_directory('realsense2_camera'), 'launch', 'rs_launch.py')),
            launch_arguments=cam_args.items()))
        actions.append(GroupAction(cam_group, scoped=True))

    # --- IMU orientation (D435i only gives raw gyro/accel) -------------------
    if use_imu:
        actions.append(Node(
            package='imu_filter_madgwick', executable='imu_filter_madgwick_node', output='screen',
            parameters=[{'use_mag': False, 'world_frame': 'enu', 'publish_tf': False}],
            remappings=[('imu/data_raw', '/camera/imu')]))

    # --- RTAB-Map ------------------------------------------------------------
    if image == 'infra':
        img_remaps = [
            ('rgb/image', '/camera/infra1/image_rect_raw'),
            ('rgb/camera_info', '/camera/infra1/camera_info'),
            ('depth/image', '/camera/depth/image_rect_raw')]
    else:
        img_remaps = [
            ('rgb/image', '/camera/color/image_raw'),
            ('rgb/camera_info', '/camera/color/camera_info'),
            ('depth/image', '/camera/aligned_depth_to_color/image_raw')]
    remappings = img_remaps + [('imu', '/imu/data')]

    common = {
        'frame_id': arg('frame_id'),
        'subscribe_depth': True,
        'subscribe_odom_info': True,
        # Exact sync works for the live camera (enable_sync); recordings are safer with approx.
        'approx_sync': source != 'camera',
        'wait_imu_to_init': use_imu,
    }
    # The YAML comes last so it can override the defaults above.
    extra = [config] if config else []

    actions.append(Node(
        package='rtabmap_odom', executable='rgbd_odometry', output='screen',
        parameters=[common] + extra,
        remappings=remappings))

    slam_params = dict(common, database_path=db_path)
    slam_args = []
    if localization:
        slam_params.update({'Mem/IncrementalMemory': 'false', 'Mem/InitWMWithAllNodes': 'true'})
    elif arg('delete_db') == 'true':
        slam_args.append('-d')   # start a fresh map each run

    actions.append(Node(
        package='rtabmap_slam', executable='rtabmap', output='screen',
        parameters=[slam_params] + extra,
        remappings=remappings,
        arguments=slam_args))

    if arg('viz') == 'true':
        actions.append(Node(
            package='rtabmap_viz', executable='rtabmap_viz', output='screen',
            parameters=[common],
            remappings=remappings))

    return actions


def generate_launch_description():
    return LaunchDescription([
        DeclareLaunchArgument('source', default_value='camera',
                              description='camera | rsbag (Intel .bag via librealsense) | ros2bag (external ros2 bag play --clock)'),
        DeclareLaunchArgument('bag', default_value='',
                              description='Path to Intel .bag file when source:=rsbag'),
        DeclareLaunchArgument('image', default_value='infra',
                              description='infra (infra1 + depth, emitter off) | color (color + aligned depth)'),
        DeclareLaunchArgument('profile', default_value='640,480,30',
                              description='Live camera stream profile width,height,fps'),
        DeclareLaunchArgument('imu', default_value='true',
                              description='Use the D435i IMU'),
        DeclareLaunchArgument('unite_imu_method', default_value='2',
                              description='1-copy, 2-linear_interpolation. Try 1 if /camera/imu stops publishing.'),
        DeclareLaunchArgument('frame_id', default_value='camera_link',
                              description='Robot base frame; switch to base_link once mounted on the robot'),
        DeclareLaunchArgument('database_path', default_value='~/.ros/rtabmap.db'),
        DeclareLaunchArgument('config', default_value='',
                              description='Optional YAML with extra RTAB-Map parameters (odometry + rtabmap)'),
        DeclareLaunchArgument('delete_db', default_value='true',
                              description='Delete the map database on start (mapping mode only)'),
        DeclareLaunchArgument('localization', default_value='false',
                              description='Localize in an existing map instead of building a new one'),
        DeclareLaunchArgument('viz', default_value='true',
                              description='Start rtabmap_viz'),
        OpaqueFunction(function=launch_setup),
    ])
