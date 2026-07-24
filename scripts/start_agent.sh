#!/bin/bash
set -euo pipefail

WORKSPACE_DIR="${WORKSPACE_DIR:-${ARENA_WS_DIR:-/opt/arena_ws}}"
ARENA_DIR="${ARENA_DIR:-$WORKSPACE_DIR/src/Arena}"
export WORKSPACE_DIR ARENA_DIR
COMMON_SH="$ARENA_DIR/arena_ai_integration/scripts/arena_ai_common.sh"
if [ -f "$COMMON_SH" ]; then
    # shellcheck disable=SC1090
    source "$COMMON_SH"
fi

AGENT_TYPE="${AGENT_TYPE:-socialnav}"
ENABLE_HUMAN_TRACKING="${ENABLE_HUMAN_TRACKING:-true}"
ENABLE_VISUALIZATION="${ENABLE_VISUALIZATION:-true}"
TRAIN_MODE="${TRAIN_MODE:-false}"
SIM="${SIM:-isaac}"
WORLD="${WORLD:-hospital_1}"
ROBOT="${ROBOT:-turtlebot}"
TM_ROBOTS="${TM_ROBOTS:-scenario}"
TM_OBSTACLES="${TM_OBSTACLES:-scenario}"
MOBILE="${MOBILE:-nav2}"
GLOBAL_PLANNER="${GLOBAL_PLANNER:-navfn}"
LOCAL_PLANNER="${LOCAL_PLANNER:-dwb}"
INTER_PLANNER="${INTER_PLANNER:-default}"
ARENA_HEADLESS="${ARENA_HEADLESS:-1}"
ARENA_AI_DWB_INTEGRATION="${ARENA_AI_DWB_INTEGRATION:-path_adapter}"
ARENA_AI_DWB_HARD_GATE="${ARENA_AI_DWB_HARD_GATE:-false}"
ARENA_AI_COORDINATE_MODE="${ARENA_AI_COORDINATE_MODE:-xz_to_ros}"
ARENA_AI_FALLBACK_TO_DWB="${ARENA_AI_FALLBACK_TO_DWB:-true}"
RVIZ_NS="${RVIZ_NS:-/arena/env_0/task_generator_node}"
ARENA_AI_TASK_NAMESPACE="${ARENA_AI_TASK_NAMESPACE:-$RVIZ_NS}"
ARENA_AI_ROBOT_NAMESPACE="${ARENA_AI_ROBOT_NAMESPACE:-$ARENA_AI_TASK_NAMESPACE/$ROBOT}"
ARENA_AI_ROBOT_FRAME="${ARENA_AI_ROBOT_FRAME:-$ROBOT/base_link}"
ARENA_AI_INSTRUCTION_TOPIC="${ARENA_AI_INSTRUCTION_TOPIC:-/nav_instruction}"
ARENA_AI_HUMAN_DETECTIONS_TOPIC="${ARENA_AI_HUMAN_DETECTIONS_TOPIC:-/detections/humans}"
ARENA_AI_IMAGE_TOPIC="${ARENA_AI_IMAGE_TOPIC:-$ARENA_AI_ROBOT_NAMESPACE/rgbd_camera/image}"
ARENA_AI_DWB_CMD_TOPIC="${ARENA_AI_DWB_CMD_TOPIC:-$ARENA_AI_ROBOT_NAMESPACE/cmd_vel_nav}"
ARENA_AI_CMD_VEL_TOPIC="${ARENA_AI_CMD_VEL_TOPIC:-$ARENA_AI_ROBOT_NAMESPACE/cmd_vel}"
ARENA_AI_PLAN_TOPIC="${ARENA_AI_PLAN_TOPIC:-$ARENA_AI_ROBOT_NAMESPACE/plan}"

AI_INTEGRATION_DIR="$ARENA_DIR/arena_ai_integration"

case "$AGENT_TYPE" in
  socialnav)
    MODEL_CONFIG="${MODEL_CONFIG:-$AI_INTEGRATION_DIR/config/models/socialnav_film.yaml}"
    MODEL_CHECKPOINT="${MODEL_CHECKPOINT:-$AI_INTEGRATION_DIR/checkpoints/SocialNav_1_path.pth}"
    PARAMS_FILE="socialnav_params.yaml"
    ;;
  urbannav)
    MODEL_CONFIG="${MODEL_CONFIG:-$AI_INTEGRATION_DIR/config/models/urbannav_film.yaml}"
    MODEL_CHECKPOINT="${MODEL_CHECKPOINT:-$AI_INTEGRATION_DIR/checkpoints/UrbanNav_FiLM.pth}"
    PARAMS_FILE="urbannav_params.yaml"
    ENABLE_HUMAN_TRACKING="${ENABLE_HUMAN_TRACKING:-false}"
    ;;
  lelan)
    MODEL_CONFIG="${MODEL_CONFIG:-$AI_INTEGRATION_DIR/config/models/lelan.yaml}"
    MODEL_CHECKPOINT="${MODEL_CHECKPOINT:-$AI_INTEGRATION_DIR/checkpoints/LeLan_latest.pth}"
    PARAMS_FILE="lelan_params.yaml"
    ENABLE_HUMAN_TRACKING="${ENABLE_HUMAN_TRACKING:-false}"
    ;;
  *)
    echo "[ERROR] Unsupported AGENT_TYPE=$AGENT_TYPE (use socialnav, urbannav, or lelan)"
    exit 1
    ;;
esac

cleanup() {
    echo
    echo "[INFO] Stopping AI controller session (agent=$AGENT_TYPE)..."
    pkill -P $$ 2>/dev/null || true
    sleep 1
    pkill -f "ai_controller|human_states_bridge.py|semantic_laser_filter.py" 2>/dev/null || true
    pkill -f "nav2_lifecycle_manager|task_generator_node|bt_navigator|planner_server" 2>/dev/null || true
}
trap cleanup INT TERM

echo "═══════════════════════════════════════════════════════════════════════════"
echo "[INFO] Starting Arena AI Integration (agent=$AGENT_TYPE)"
echo "═══════════════════════════════════════════════════════════════════════════"

if [ ! -f "$WORKSPACE_DIR/install/setup.bash" ]; then
    echo "[ERROR] Workspace not built: $WORKSPACE_DIR/install/setup.bash missing"
    exit 1
fi

if declare -F arena_ai_source_workspace >/dev/null 2>&1; then
    arena_ai_source_workspace
else
    set +u
    source "$WORKSPACE_DIR/install/setup.bash"
    set -u
fi

if ! declare -F arena >/dev/null 2>&1; then
    echo "[ERROR] Arena shell function is not available. Run: source $WORKSPACE_DIR/source"
    exit 1
fi

if declare -F arena_ai_prepare_isaac_urdf >/dev/null 2>&1; then
    arena_ai_prepare_isaac_urdf "$SIM" "$ROBOT"
fi

if [ ! -f "$MODEL_CHECKPOINT" ]; then
    echo "[ERROR] Checkpoint not found: $MODEL_CHECKPOINT"
    exit 1
fi

if [ "$AGENT_TYPE" = "socialnav" ]; then
    echo "[INFO] Starting Human States Bridge..."
    python3 -m arena_ai_integration.nodes.human_states_bridge \
        --ros-args \
        -p use_sim_time:=true \
        -p task_namespace:="$ARENA_AI_TASK_NAMESPACE" \
        -p output_topic:="$ARENA_AI_HUMAN_DETECTIONS_TOPIC" &
    sleep 1
fi

echo "[INFO] Launching Arena simulator..."
arena launch \
    sim:="$SIM" \
    world:="$WORLD" \
    robot:="$ROBOT" \
    tm_robots:="$TM_ROBOTS" \
    tm_obstacles:="$TM_OBSTACLES" \
    mobile:="$MOBILE" \
    global_planner:="$GLOBAL_PLANNER" \
    local_planner:="$LOCAL_PLANNER" \
    inter_planner:="$INTER_PLANNER" \
    use_sim_time:=true \
    headless:="$ARENA_HEADLESS" \
    train_mode:="$TRAIN_MODE" &
ARENA_PID=$!
sleep 12

if [ "$AGENT_TYPE" = "socialnav" ]; then
    echo "[INFO] Starting Semantic Laser Filter..."
    python3 -m arena_ai_integration.nodes.semantic_laser_filter \
        --ros-args \
        -p use_sim_time:=true \
        -p detections_topic:="$ARENA_AI_HUMAN_DETECTIONS_TOPIC" \
        -p input_scan_topic:="$ARENA_AI_ROBOT_NAMESPACE/lidar" \
        -p output_scan_topic:="$ARENA_AI_ROBOT_NAMESPACE/lidar_static" \
        -p target_frame:="$ARENA_AI_ROBOT_FRAME" &
    sleep 1
fi

PKG_SHARE="$(ros2 pkg prefix arena_ai_integration)/share/arena_ai_integration"

echo "[INFO] Starting unified AI controller (robot_ns=$ARENA_AI_ROBOT_NAMESPACE)..."
ros2 launch arena_ai_integration ai_controller.launch.py \
    agent_type:="$AGENT_TYPE" \
    params_file:="$PKG_SHARE/config/$PARAMS_FILE" \
    agent_name:="$AGENT_TYPE" \
    model_config_path:="$MODEL_CONFIG" \
    model_checkpoint_path:="$MODEL_CHECKPOINT" \
    enable_human_tracking:="$ENABLE_HUMAN_TRACKING" \
    enable_bev_visualization:="$ENABLE_VISUALIZATION" \
    dwb_integration_mode:="$ARENA_AI_DWB_INTEGRATION" \
    use_dwb_hard_gate:="$ARENA_AI_DWB_HARD_GATE" \
    coordinate_mode:="$ARENA_AI_COORDINATE_MODE" \
    fallback_to_dwb:="$ARENA_AI_FALLBACK_TO_DWB" \
    robot_namespace:="$ARENA_AI_ROBOT_NAMESPACE" \
    robot_frame:="$ARENA_AI_ROBOT_FRAME" \
    instruction_topic:="$ARENA_AI_INSTRUCTION_TOPIC" \
    human_detections_topic:="$ARENA_AI_HUMAN_DETECTIONS_TOPIC" \
    image_topic:="$ARENA_AI_IMAGE_TOPIC" \
    dwb_cmd_topic:="$ARENA_AI_DWB_CMD_TOPIC" \
    cmd_vel_topic:="$ARENA_AI_CMD_VEL_TOPIC" \
    plan_topic:="$ARENA_AI_PLAN_TOPIC" \
    use_sim_time:=true &

sleep 3

if [ "$ENABLE_VISUALIZATION" = "true" ]; then
    RVIZ_CONFIG="$ARENA_DIR/arena_bringup/config/default.rviz"
    if [ -f "$RVIZ_CONFIG" ]; then
        ros2 run rviz2 rviz2 -d "$RVIZ_CONFIG" &
    fi
fi

wait
