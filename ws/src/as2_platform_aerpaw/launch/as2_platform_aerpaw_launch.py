"""Launch the AERPAW platform node."""

import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def generate_launch_description():
    package_folder = get_package_share_directory('as2_platform_aerpaw')

    return LaunchDescription([
        DeclareLaunchArgument(
            'namespace',
            default_value='drone0',
            description='Drone namespace'),
        DeclareLaunchArgument(
            'control_modes_file',
            default_value=os.path.join(package_folder, 'config', 'control_modes.yaml'),
            description='Command types this platform accepts'),
        DeclareLaunchArgument(
            'platform_config_file',
            default_value=os.path.join(package_folder, 'config', 'platform_config_file.yaml'),
            description='Platform settings'),

        Node(
            package='as2_platform_aerpaw',
            executable='as2_platform_aerpaw_node',
            name='platform',
            namespace=LaunchConfiguration('namespace'),
            output='screen',
            emulate_tty=True,
            parameters=[
                LaunchConfiguration('platform_config_file'),
                {'control_modes_file': LaunchConfiguration('control_modes_file')},
            ],
        ),
    ])
