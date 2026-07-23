#!/usr/bin/env python3
"""Launch unified AI controller with agent_type parameter."""

import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, ExecuteProcess
from launch.substitutions import LaunchConfiguration


def generate_launch_description():
    pkg_share = get_package_share_directory('arena_ai_integration')

    agent_type = LaunchConfiguration('agent_type')
    params_file = LaunchConfiguration('params_file')
    agent_name = LaunchConfiguration('agent_name')
    model_config_path = LaunchConfiguration('model_config_path')
    model_checkpoint_path = LaunchConfiguration('model_checkpoint_path')
    enable_human_tracking = LaunchConfiguration('enable_human_tracking')
    enable_bev_visualization = LaunchConfiguration('enable_bev_visualization')
    dwb_integration_mode = LaunchConfiguration('dwb_integration_mode')
    use_dwb_hard_gate = LaunchConfiguration('use_dwb_hard_gate')
    coordinate_mode = LaunchConfiguration('coordinate_mode')
    fallback_to_dwb = LaunchConfiguration('fallback_to_dwb')
    robot_namespace = LaunchConfiguration('robot_namespace')
    robot_frame = LaunchConfiguration('robot_frame')
    instruction_topic = LaunchConfiguration('instruction_topic')
    human_detections_topic = LaunchConfiguration('human_detections_topic')
    image_topic = LaunchConfiguration('image_topic')
    dwb_cmd_topic = LaunchConfiguration('dwb_cmd_topic')
    cmd_vel_topic = LaunchConfiguration('cmd_vel_topic')
    plan_topic = LaunchConfiguration('plan_topic')
    use_sim_time = LaunchConfiguration('use_sim_time')

    ai_python = os.environ.get('ARENA_AI_PYTHON', 'python3')

    controller_node = ExecuteProcess(
        cmd=[
            ai_python,
            '-m',
            'arena_ai_integration.nodes.ai_controller_node',
            '--ros-args',
            '-r',
            '__node:=ai_controller',
            '-p',
            ['agent_type:=', agent_type],
            '--params-file',
            os.path.join(pkg_share, 'config', 'base_params.yaml'),
            '--params-file',
            params_file,
            '-p',
            ['agent_name:=', agent_name],
            '-p',
            ['model_config_path:=', model_config_path],
            '-p',
            ['model_checkpoint_path:=', model_checkpoint_path],
            '-p',
            ['enable_human_tracking:=', enable_human_tracking],
            '-p',
            ['enable_bev_visualization:=', enable_bev_visualization],
            '-p',
            ['dwb_integration_mode:=', dwb_integration_mode],
            '-p',
            ['use_dwb_hard_gate:=', use_dwb_hard_gate],
            '-p',
            ['coordinate_mode:=', coordinate_mode],
            '-p',
            ['fallback_to_dwb:=', fallback_to_dwb],
            '-p',
            ['robot_namespace:=', robot_namespace],
            '-p',
            ['robot_frame:=', robot_frame],
            '-p',
            ['instruction_topic:=', instruction_topic],
            '-p',
            ['human_detections_topic:=', human_detections_topic],
            '-p',
            ['image_topic:=', image_topic],
            '-p',
            ['dwb_cmd_topic:=', dwb_cmd_topic],
            '-p',
            ['cmd_vel_topic:=', cmd_vel_topic],
            '-p',
            ['plan_topic:=', plan_topic],
            '-p',
            ['use_sim_time:=', use_sim_time],
        ],
        output='screen',
    )

    agent_type_arg = DeclareLaunchArgument(
        'agent_type',
        default_value='socialnav',
        description='AI agent: socialnav, urbannav, lelan',
    )

    params_file_arg = DeclareLaunchArgument(
        'params_file',
        default_value=os.path.join(pkg_share, 'config', 'socialnav_params.yaml'),
        description='Agent-specific parameter YAML: socialnav_params, urbannav_params, or lelan_params',
    )

    agent_name_arg = DeclareLaunchArgument('agent_name', default_value='')
    model_config_path_arg = DeclareLaunchArgument('model_config_path', default_value='')
    model_checkpoint_path_arg = DeclareLaunchArgument('model_checkpoint_path', default_value='')
    enable_human_tracking_arg = DeclareLaunchArgument('enable_human_tracking', default_value='true')
    enable_bev_visualization_arg = DeclareLaunchArgument('enable_bev_visualization', default_value='false')
    dwb_integration_mode_arg = DeclareLaunchArgument('dwb_integration_mode', default_value='path_adapter')
    use_dwb_hard_gate_arg = DeclareLaunchArgument('use_dwb_hard_gate', default_value='false')
    coordinate_mode_arg = DeclareLaunchArgument('coordinate_mode', default_value='')
    fallback_to_dwb_arg = DeclareLaunchArgument('fallback_to_dwb', default_value='true')
    robot_namespace_arg = DeclareLaunchArgument('robot_namespace', default_value='/task_generator_node/turtlebot')
    robot_frame_arg = DeclareLaunchArgument('robot_frame', default_value='')
    instruction_topic_arg = DeclareLaunchArgument('instruction_topic', default_value='/nav_instruction')
    human_detections_topic_arg = DeclareLaunchArgument('human_detections_topic', default_value='/detections/humans')
    image_topic_arg = DeclareLaunchArgument('image_topic', default_value='')
    dwb_cmd_topic_arg = DeclareLaunchArgument('dwb_cmd_topic', default_value='')
    cmd_vel_topic_arg = DeclareLaunchArgument('cmd_vel_topic', default_value='')
    plan_topic_arg = DeclareLaunchArgument('plan_topic', default_value='')
    use_sim_time_arg = DeclareLaunchArgument('use_sim_time', default_value='true')

    return LaunchDescription([
        agent_type_arg,
        params_file_arg,
        agent_name_arg,
        model_config_path_arg,
        model_checkpoint_path_arg,
        enable_human_tracking_arg,
        enable_bev_visualization_arg,
        dwb_integration_mode_arg,
        use_dwb_hard_gate_arg,
        coordinate_mode_arg,
        fallback_to_dwb_arg,
        robot_namespace_arg,
        robot_frame_arg,
        instruction_topic_arg,
        human_detections_topic_arg,
        image_topic_arg,
        dwb_cmd_topic_arg,
        cmd_vel_topic_arg,
        plan_topic_arg,
        use_sim_time_arg,
        controller_node,
    ])
