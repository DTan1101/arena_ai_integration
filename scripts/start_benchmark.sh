#!/bin/bash
set -euo pipefail

export WORKSPACE_DIR="${WORKSPACE_DIR:-${ARENA_WS_DIR:-/opt/arena_ws}}"
export ARENA_WS_DIR="$WORKSPACE_DIR"
export ARENA_DIR="${ARENA_DIR:-$WORKSPACE_DIR/src/Arena}"

COMMON_SH="$ARENA_DIR/arena_ai_integration/scripts/arena_ai_common.sh"
if [ -f "$COMMON_SH" ]; then
    # shellcheck disable=SC1090
    source "$COMMON_SH"
fi

echo "=== CHECKING SYSTEM RESOURCES ==="

WATCHES=$(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null || echo 0)
INSTANCES=$(cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null || echo 0)
FREE_SPACE_GB=$(df -BG "$WORKSPACE_DIR" | awk 'NR==2 {print $4}' | tr -d 'G')
FAIL_FLAG=0

if [ "$WATCHES" -lt 524288 ]; then
    echo -e "\e[31m[FAIL]\e[0m fs.inotify.max_user_watches is too low: $WATCHES (requires >= 524288)"
    FAIL_FLAG=1
else
    echo -e "\e[32m[PASS]\e[0m inotify watches: $WATCHES"
fi

if [ "$INSTANCES" -lt 1024 ]; then
    echo -e "\e[31m[FAIL]\e[0m fs.inotify.max_user_instances is too low: $INSTANCES (requires >= 1024)"
    FAIL_FLAG=1
else
    echo -e "\e[32m[PASS]\e[0m inotify instances: $INSTANCES"
fi

if [ "$FREE_SPACE_GB" -lt 4 ]; then
    echo -e "\e[31m[FAIL]\e[0m $WORKSPACE_DIR free space is too low: ${FREE_SPACE_GB}GB (recommended >= 10GB)"
    FAIL_FLAG=1
else
    echo -e "\e[32m[PASS]\e[0m $WORKSPACE_DIR free space: ${FREE_SPACE_GB}GB"
fi

if [ "$FAIL_FLAG" -eq 1 ]; then
    echo -e "\e[31m>>> INSUFFICIENT RESOURCES. ABORTING BENCHMARK. <<<\e[0m"
    exit 1
fi

echo -e "\e[32m=== ALL CHECKS PASSED. STARTING BENCHMARK ===\e[0m"
echo ""

AGENT_TYPE="${AGENT_TYPE:-socialnav}"
SIM="${SIM:-isaac}"
WORLD="${WORLD:-hospital_1}"
ROBOT="${ROBOT:-turtlebot}"
TM_ROBOTS="${TM_ROBOTS:-scenario}"
TM_OBSTACLES="${TM_OBSTACLES:-scenario}"
BENCHMARK_SCENARIOS="${BENCHMARK_SCENARIOS:-${SCENARIOS:-default}}"
BENCHMARK_EPISODES="${BENCHMARK_EPISODES:-${EPISODES:-1}}"
BENCHMARK_TIMEOUT="${BENCHMARK_TIMEOUT:-180s}"
BENCHMARK_SCALE_EPISODES="${BENCHMARK_SCALE_EPISODES:-1.0}"
BENCHMARK_ENV_N="${BENCHMARK_ENV_N:-1}"
ARENA_HEADLESS="${ARENA_HEADLESS:-1}"
BENCHMARK_RUN_ID="${BENCHMARK_RUN_ID:-}"
BENCHMARK_DATA_ROOT="${BENCHMARK_DATA_ROOT:-$WORKSPACE_DIR/data/benchmarks}"
ARENA_AI_SIDECAR_LOG_DIR_EXPLICIT="${ARENA_AI_SIDECAR_LOG_DIR+x}"
ARENA_AI_SIDECAR_LOG_ROOT="${ARENA_AI_SIDECAR_LOG_ROOT:-$BENCHMARK_DATA_ROOT/arena_ai_sidecars}"
ARENA_AI_SIDECAR_LOG_DIR="${ARENA_AI_SIDECAR_LOG_DIR:-$ARENA_AI_SIDECAR_LOG_ROOT/$(date +%Y%m%d-%H%M%S)-$AGENT_TYPE}"
LOCAL_PLANNER="${LOCAL_PLANNER:-dwb}"
GLOBAL_PLANNER="${GLOBAL_PLANNER:-navfn}"
INTER_PLANNER="${INTER_PLANNER:-default}"
MOBILE="${MOBILE:-nav2}"
TRAIN_MODE="${TRAIN_MODE:-false}"

START_AI_CONTROLLER="${START_AI_CONTROLLER:-1}"
ENABLE_HUMAN_TRACKING="${ENABLE_HUMAN_TRACKING:-true}"
ENABLE_VISUALIZATION="${ENABLE_VISUALIZATION:-false}"
START_RVIZ="${START_RVIZ:-0}"
RVIZ_NS="${RVIZ_NS:-/arena/env_0/task_generator_node}"
RVIZ_VIEW="${RVIZ_VIEW:-map}"
RVIZ_ROBOT="${RVIZ_ROBOT:-0}"
ARENA_AI_TASK_NAMESPACE="${ARENA_AI_TASK_NAMESPACE:-$RVIZ_NS}"
ARENA_AI_ROBOT_NAMESPACE="${ARENA_AI_ROBOT_NAMESPACE:-$ARENA_AI_TASK_NAMESPACE/$ROBOT}"
ARENA_AI_ROBOT_FRAME="${ARENA_AI_ROBOT_FRAME:-$ROBOT/base_link}"
ARENA_AI_INSTRUCTION_TOPIC="${ARENA_AI_INSTRUCTION_TOPIC:-/nav_instruction}"
ARENA_AI_HUMAN_DETECTIONS_TOPIC="${ARENA_AI_HUMAN_DETECTIONS_TOPIC:-/detections/humans}"
ARENA_AI_IMAGE_TOPIC="${ARENA_AI_IMAGE_TOPIC:-$ARENA_AI_ROBOT_NAMESPACE/rgbd_camera/image}"
ARENA_AI_DWB_CMD_TOPIC="${ARENA_AI_DWB_CMD_TOPIC:-$ARENA_AI_ROBOT_NAMESPACE/cmd_vel_nav}"
ARENA_AI_CMD_VEL_TOPIC="${ARENA_AI_CMD_VEL_TOPIC:-$ARENA_AI_ROBOT_NAMESPACE/cmd_vel}"
ARENA_AI_PLAN_TOPIC="${ARENA_AI_PLAN_TOPIC:-$ARENA_AI_ROBOT_NAMESPACE/plan}"
BENCHMARK_CONDA_ENV="${BENCHMARK_CONDA_ENV:-socialnav}"
ARENA_AI_PYTHONNOUSERSITE="${ARENA_AI_PYTHONNOUSERSITE:-1}"
ARENA_AI_DWB_INTEGRATION="${ARENA_AI_DWB_INTEGRATION:-path_adapter}"
ARENA_AI_DWB_HARD_GATE="${ARENA_AI_DWB_HARD_GATE:-false}"
ARENA_AI_COORDINATE_MODE="${ARENA_AI_COORDINATE_MODE:-xz_to_ros}"
ARENA_AI_FALLBACK_TO_DWB="${ARENA_AI_FALLBACK_TO_DWB:-true}"
export ARENA_AI_PYTHONNOUSERSITE
export ARENA_AI_DWB_INTEGRATION ARENA_AI_DWB_HARD_GATE ARENA_AI_COORDINATE_MODE ARENA_AI_FALLBACK_TO_DWB

AI_INTEGRATION_DIR="$ARENA_DIR/arena_ai_integration"
AI_SIDECAR_PIDS=()
BASE_BENCHMARK_RUN_ID="$BENCHMARK_RUN_ID"

cleanup() {
    local status=$?
    trap - EXIT INT TERM
    stop_ai_sidecars
    exit "$status"
}
trap cleanup EXIT INT TERM

stop_ai_sidecars() {
    if [ "${#AI_SIDECAR_PIDS[@]}" -gt 0 ]; then
        echo ""
        echo "[INFO] Stopping Arena AI benchmark sidecars..."
        for pid in "${AI_SIDECAR_PIDS[@]}"; do
            kill "$pid" 2>/dev/null || true
        done
        for pid in "${AI_SIDECAR_PIDS[@]}"; do
            wait "$pid" 2>/dev/null || true
        done
        AI_SIDECAR_PIDS=()
    fi
    pkill -f "arena_ai_integration.nodes.ai_controller_node" 2>/dev/null || true
    pkill -f "arena_ai_integration.nodes.human_states_bridge" 2>/dev/null || true
    pkill -f "arena_ai_integration.nodes.semantic_laser_filter" 2>/dev/null || true
}

build_ai_runtime_library_path() {
    local python_bin="$1"

    PYTHONNOUSERSITE="$ARENA_AI_PYTHONNOUSERSITE" "$python_bin" - <<'PY' 2>/dev/null || true
from pathlib import Path
import sys

prefix = Path(sys.executable).resolve().parents[1]
paths = [prefix / "lib"]
for site_packages in (prefix / "lib").glob("python*/site-packages"):
    paths.extend(sorted((site_packages / "nvidia").glob("*/lib")))

seen = set()
valid = []
for path in paths:
    if path.is_dir():
        resolved = str(path.resolve())
        if resolved not in seen:
            seen.add(resolved)
            valid.append(resolved)

print(":".join(valid))
PY
}

activate_benchmark_conda_env() {
    if [ "$START_AI_CONTROLLER" != "1" ] || [ "$AGENT_TYPE" = "none" ]; then
        return 0
    fi

    if [ -z "$BENCHMARK_CONDA_ENV" ] || [ "$BENCHMARK_CONDA_ENV" = "none" ]; then
        echo "[INFO] BENCHMARK_CONDA_ENV is empty/none; using current python environment."
        local python_bin
        python_bin="$(python3 -c 'import sys; print(sys.executable)')"
        ARENA_AI_PYTHON="${ARENA_AI_PYTHON:-$python_bin}"
        ARENA_AI_RUNTIME_LIBRARY_PATH="$(build_ai_runtime_library_path "$ARENA_AI_PYTHON")"
        ARENA_AI_LD_LIBRARY_PATH="$ARENA_AI_RUNTIME_LIBRARY_PATH"
        if [ -n "${LD_LIBRARY_PATH:-}" ]; then
            ARENA_AI_LD_LIBRARY_PATH="${ARENA_AI_LD_LIBRARY_PATH:+$ARENA_AI_LD_LIBRARY_PATH:}$LD_LIBRARY_PATH"
        fi
        export ARENA_AI_PYTHON ARENA_AI_RUNTIME_LIBRARY_PATH ARENA_AI_LD_LIBRARY_PATH
        echo "[INFO] Arena AI Python: $ARENA_AI_PYTHON"
        echo "[INFO] Arena AI runtime library path: ${ARENA_AI_RUNTIME_LIBRARY_PATH:-<empty>}"
        return 0
    fi

    local conda_sh=""
    local conda_base=""

    if [ "${CONDA_DEFAULT_ENV:-}" != "$BENCHMARK_CONDA_ENV" ]; then
        if [ -n "${BENCHMARK_CONDA_SH:-}" ]; then
            conda_sh="$BENCHMARK_CONDA_SH"
        fi
        if [ ! -f "$conda_sh" ] && [ -n "${CONDA_EXE:-}" ]; then
            conda_base="$(dirname "$(dirname "$CONDA_EXE")")"
            conda_sh="$conda_base/etc/profile.d/conda.sh"
        fi
        if [ ! -f "$conda_sh" ] && [ -n "${CONDA_PREFIX:-}" ] && [ -f "$CONDA_PREFIX/etc/profile.d/conda.sh" ]; then
            conda_sh="$CONDA_PREFIX/etc/profile.d/conda.sh"
        fi
        if [ ! -f "$conda_sh" ] && [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
            conda_sh="$HOME/miniconda3/etc/profile.d/conda.sh"
        fi
        if [ ! -f "$conda_sh" ] && [ -f "$HOME/anaconda3/etc/profile.d/conda.sh" ]; then
            conda_sh="$HOME/anaconda3/etc/profile.d/conda.sh"
        fi
        if [ ! -f "$conda_sh" ] && [ -f "$HOME/miniforge3/etc/profile.d/conda.sh" ]; then
            conda_sh="$HOME/miniforge3/etc/profile.d/conda.sh"
        fi
        if [ ! -f "$conda_sh" ] && [ -f "$HOME/mambaforge/etc/profile.d/conda.sh" ]; then
            conda_sh="$HOME/mambaforge/etc/profile.d/conda.sh"
        fi
        if [ ! -f "$conda_sh" ] && [ -f "/opt/conda/etc/profile.d/conda.sh" ]; then
            conda_sh="/opt/conda/etc/profile.d/conda.sh"
        fi
        if [ ! -f "$conda_sh" ] && [ -f "/opt/miniconda3/etc/profile.d/conda.sh" ]; then
            conda_sh="/opt/miniconda3/etc/profile.d/conda.sh"
        fi
        if [ ! -f "$conda_sh" ] && [ -f "/opt/miniforge3/etc/profile.d/conda.sh" ]; then
            conda_sh="/opt/miniforge3/etc/profile.d/conda.sh"
        fi
        if [ ! -f "$conda_sh" ] && command -v conda >/dev/null 2>&1; then
            conda_base="$(conda info --base 2>/dev/null || true)"
            if [ -n "$conda_base" ]; then
                conda_sh="$conda_base/etc/profile.d/conda.sh"
            fi
        fi
        if [ ! -f "$conda_sh" ]; then
            echo "[ERROR] Could not find conda initialization script for BENCHMARK_CONDA_ENV=$BENCHMARK_CONDA_ENV"
            echo "[ERROR] Set BENCHMARK_CONDA_SH=/path/to/etc/profile.d/conda.sh, activate the env before running,"
            echo "[ERROR] or set BENCHMARK_CONDA_ENV=none to use the current python environment."
            exit 1
        fi

        # shellcheck disable=SC1090
        source "$conda_sh"
        echo "[INFO] Activating conda environment: $BENCHMARK_CONDA_ENV"
        conda activate "$BENCHMARK_CONDA_ENV"
    else
        echo "[INFO] Conda environment already active: $BENCHMARK_CONDA_ENV"
    fi

    local python_bin
    python_bin="$(python3 -c 'import sys; print(sys.executable)')"
    ARENA_AI_PYTHON="${ARENA_AI_PYTHON:-$python_bin}"
    ARENA_AI_RUNTIME_LIBRARY_PATH="$(build_ai_runtime_library_path "$ARENA_AI_PYTHON")"
    ARENA_AI_LD_LIBRARY_PATH="$ARENA_AI_RUNTIME_LIBRARY_PATH"
    if [ -n "${LD_LIBRARY_PATH:-}" ]; then
        ARENA_AI_LD_LIBRARY_PATH="${ARENA_AI_LD_LIBRARY_PATH:+$ARENA_AI_LD_LIBRARY_PATH:}$LD_LIBRARY_PATH"
    fi
    export ARENA_AI_PYTHON ARENA_AI_RUNTIME_LIBRARY_PATH ARENA_AI_LD_LIBRARY_PATH

    echo "[INFO] Arena AI Python: $ARENA_AI_PYTHON"
    echo "[INFO] Arena AI runtime library path: ${ARENA_AI_RUNTIME_LIBRARY_PATH:-<empty>}"
}

resolve_agent_assets() {
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
        none)
            MODEL_CONFIG=""
            MODEL_CHECKPOINT=""
            PARAMS_FILE=""
            ;;
        *)
            echo "[ERROR] Unsupported AGENT_TYPE=$AGENT_TYPE (use socialnav, urbannav, lelan, or none)"
            exit 1
            ;;
    esac
}

start_ai_sidecars() {
    if [ "$START_AI_CONTROLLER" != "1" ] || [ "$AGENT_TYPE" = "none" ]; then
        echo "[INFO] AI sidecars disabled."
        return 0
    fi

    if [ ! -f "$MODEL_CHECKPOINT" ]; then
        echo "[ERROR] Checkpoint not found: $MODEL_CHECKPOINT"
        exit 1
    fi

    mkdir -p "$ARENA_AI_SIDECAR_LOG_DIR"
    echo "[INFO] Arena AI sidecar logs: $ARENA_AI_SIDECAR_LOG_DIR"

    local pkg_share
    pkg_share="$(ros2 pkg prefix arena_ai_integration)/share/arena_ai_integration"

    if [ "$AGENT_TYPE" = "socialnav" ]; then
        echo "[INFO] Starting Human States Bridge..."
        python3 -m arena_ai_integration.nodes.human_states_bridge \
            --ros-args \
            -p use_sim_time:=true \
            -p task_namespace:="$ARENA_AI_TASK_NAMESPACE" \
            -p output_topic:="$ARENA_AI_HUMAN_DETECTIONS_TOPIC" \
            >"$ARENA_AI_SIDECAR_LOG_DIR/human_states_bridge.log" 2>&1 &
        AI_SIDECAR_PIDS+=("$!")
        sleep 1

        echo "[INFO] Starting Semantic Laser Filter..."
        python3 -m arena_ai_integration.nodes.semantic_laser_filter \
            --ros-args \
            -p use_sim_time:=true \
            -p detections_topic:="$ARENA_AI_HUMAN_DETECTIONS_TOPIC" \
            -p input_scan_topic:="$ARENA_AI_ROBOT_NAMESPACE/lidar" \
            -p output_scan_topic:="$ARENA_AI_ROBOT_NAMESPACE/lidar_static" \
            -p target_frame:="${ARENA_AI_ROBOT_FRAME:-turtlebot/base_link}" \
            >"$ARENA_AI_SIDECAR_LOG_DIR/semantic_laser_filter.log" 2>&1 &
        AI_SIDECAR_PIDS+=("$!")
        sleep 1
    fi

    echo "[INFO] Starting Arena AI controller (agent=$AGENT_TYPE, mode=$ARENA_AI_DWB_INTEGRATION, robot_ns=$ARENA_AI_ROBOT_NAMESPACE)..."
    LD_LIBRARY_PATH="${ARENA_AI_LD_LIBRARY_PATH:-${LD_LIBRARY_PATH:-}}" \
    PYTHONNOUSERSITE="$ARENA_AI_PYTHONNOUSERSITE" \
    ros2 launch arena_ai_integration ai_controller.launch.py \
        agent_type:="$AGENT_TYPE" \
        params_file:="$pkg_share/config/$PARAMS_FILE" \
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
        use_sim_time:=true \
        >"$ARENA_AI_SIDECAR_LOG_DIR/ai_controller.log" 2>&1 &
    AI_SIDECAR_PIDS+=("$!")
}

start_rviz_sidecar() {
    if [ "$START_RVIZ" != "1" ] && [ "$ENABLE_VISUALIZATION" != "rviz" ]; then
        return 0
    fi

    if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
        echo "[WARN] START_RVIZ requested but DISPLAY/WAYLAND_DISPLAY is not set; RViz may not open from this container."
    fi

    mkdir -p "$ARENA_AI_SIDECAR_LOG_DIR"
    echo "[INFO] Starting Arena RViz for namespace $RVIZ_NS (view=$RVIZ_VIEW, robot=$RVIZ_ROBOT)..."
    ros2 launch rviz_utils rviz_config.launch.py \
        ns:="$RVIZ_NS" \
        view:="$RVIZ_VIEW" \
        robot:="$RVIZ_ROBOT" \
        >"$ARENA_AI_SIDECAR_LOG_DIR/rviz.log" 2>&1 &
    AI_SIDECAR_PIDS+=("$!")
}

build_inline_suite() {
    WORLD="$WORLD" \
    ROBOT="$ROBOT" \
    TM_ROBOTS="$TM_ROBOTS" \
    TM_OBSTACLES="$TM_OBSTACLES" \
    BENCHMARK_SCENARIOS="$BENCHMARK_SCENARIOS" \
    BENCHMARK_EPISODES="$BENCHMARK_EPISODES" \
    BENCHMARK_TIMEOUT="$BENCHMARK_TIMEOUT" \
    python3 - <<'PY'
import json
import os

world = os.environ["WORLD"]
robot = os.environ["ROBOT"]
tm_robots = os.environ["TM_ROBOTS"]
tm_obstacles = os.environ["TM_OBSTACLES"]
episodes = int(float(os.environ["BENCHMARK_EPISODES"]))
timeout = os.environ["BENCHMARK_TIMEOUT"]
scenarios = [
    item.strip()
    for item in os.environ["BENCHMARK_SCENARIOS"].replace(";", ",").split(",")
    if item.strip()
]

stages = []
for scenario in scenarios:
    stages.append({
        "name": f"{world}_{scenario}",
        "map": world,
        "robot": robot,
        "episodes": episodes,
        "tm_robots": tm_robots,
        "tm_obstacles": tm_obstacles,
        "timeout": timeout,
        "config": {
            "scenario": {
                "file": scenario,
            },
        },
    })

print(json.dumps({"stages": stages}))
PY
}

build_inline_contest() {
    AGENT_TYPE="$AGENT_TYPE" \
    MOBILE="$MOBILE" \
    LOCAL_PLANNER="$LOCAL_PLANNER" \
    GLOBAL_PLANNER="$GLOBAL_PLANNER" \
    INTER_PLANNER="$INTER_PLANNER" \
    TRAIN_MODE="$TRAIN_MODE" \
    BENCHMARK_CONTESTANT_NAME="${BENCHMARK_CONTESTANT_NAME:-}" \
    python3 - <<'PY'
import json
import os

agent_type = os.environ["AGENT_TYPE"]
name = os.environ.get("BENCHMARK_CONTESTANT_NAME") or (
    "DWB-Baseline" if agent_type == "none" else f"{agent_type}_dwb"
)

contestant = {
    "name": name,
    "mobile": {
        "driver": os.environ["MOBILE"],
        "local_planner": os.environ["LOCAL_PLANNER"],
        "global_planner": os.environ["GLOBAL_PLANNER"],
        "inter_planner": os.environ["INTER_PLANNER"],
    },
}

if os.environ["TRAIN_MODE"].lower() in ("1", "true", "yes"):
    contestant["train_mode"] = True

print(json.dumps([contestant]))
PY
}

resolve_benchmark_arg() {
    local explicit_value="$1"
    local explicit_file="$2"
    local default_builder="$3"

    if [ -n "$explicit_value" ]; then
        printf '%s' "$explicit_value"
        return 0
    fi
    if [ -n "$explicit_file" ]; then
        if [ ! -f "$explicit_file" ]; then
            echo "[ERROR] Benchmark config file not found: $explicit_file" >&2
            return 1
        fi
        cat "$explicit_file"
        return 0
    fi
    "$default_builder"
}

if declare -F arena_ai_source_workspace >/dev/null 2>&1; then
    arena_ai_source_workspace
else
    # shellcheck disable=SC1091
    source "$WORKSPACE_DIR/install/setup.bash"
fi

if declare -F arena_ai_prepare_isaac_urdf >/dev/null 2>&1; then
    arena_ai_prepare_isaac_urdf "$SIM" "$ROBOT"
fi

if ! ros2 pkg prefix arena_evaluation >/dev/null 2>&1; then
    echo "[ERROR] arena_evaluation is not available. Build/source the workspace first."
    exit 1
fi

if ! ros2 pkg prefix arena_ai_integration >/dev/null 2>&1; then
    echo "[ERROR] arena_ai_integration is not available. Build/source the workspace first."
    exit 1
fi

SUITE_ARG="$(resolve_benchmark_arg "${BENCHMARK_SUITE:-}" "${BENCHMARK_SUITE_FILE:-}" build_inline_suite)"

run_benchmark_command() {
    local contest_arg="$1"
    local contest_label="$2"

    benchmark_cmd=(
        ros2 run arena_evaluation benchmark
        --suite "$SUITE_ARG"
        --contest "$contest_arg"
        --scale-episodes "$BENCHMARK_SCALE_EPISODES"
        --data-root "$BENCHMARK_DATA_ROOT"
    )

    if [ -n "$BENCHMARK_RUN_ID" ]; then
        benchmark_cmd+=(--run-id "$BENCHMARK_RUN_ID")
    fi
    if [ "${BENCHMARK_RETRY_FAILED:-0}" = "1" ]; then
        benchmark_cmd+=(--retry-failed)
    fi
    if [ -n "${BENCHMARK_RESUME:-}" ]; then
        benchmark_cmd+=(--resume "$BENCHMARK_RESUME")
    fi
    if [ "${BENCHMARK_NOEXIT:-0}" = "1" ]; then
        benchmark_cmd+=(--noexit)
    fi

    benchmark_cmd+=(
        sim:="$SIM"
        headless:="$ARENA_HEADLESS"
        env_n:="$BENCHMARK_ENV_N"
    )

    echo "[INFO] Benchmark suite: ${BENCHMARK_SUITE:-inline $WORLD/$BENCHMARK_SCENARIOS}"
    echo "[INFO] Benchmark contest: $contest_label"
    echo "[INFO] Benchmark data root: $BENCHMARK_DATA_ROOT"
    echo "[INFO] Running: ${benchmark_cmd[*]}"

    "${benchmark_cmd[@]}"
}

run_single_agent_benchmark() {
    local selected_agent="$1"
    local sequence_mode="${2:-0}"
    AGENT_TYPE="$selected_agent"
    if [ -z "$ARENA_AI_SIDECAR_LOG_DIR_EXPLICIT" ]; then
        ARENA_AI_SIDECAR_LOG_DIR="$ARENA_AI_SIDECAR_LOG_ROOT/$(date +%Y%m%d-%H%M%S)-$AGENT_TYPE"
    fi

    if [ "$sequence_mode" = "1" ]; then
        unset MODEL_CONFIG MODEL_CHECKPOINT PARAMS_FILE
    fi
    resolve_agent_assets
    activate_benchmark_conda_env

    if [ "$sequence_mode" = "1" ]; then
        BENCHMARK_RUN_ID=""
        if [ -n "$BASE_BENCHMARK_RUN_ID" ]; then
            BENCHMARK_RUN_ID="${BASE_BENCHMARK_RUN_ID}_${AGENT_TYPE}"
        fi
    fi

    local contest_arg
    local contest_label
    if [ "$sequence_mode" = "1" ]; then
        contest_arg="$(build_inline_contest)"
        contest_label="inline ${AGENT_TYPE}_dwb"
    else
        contest_arg="$(resolve_benchmark_arg "${BENCHMARK_CONTEST:-}" "${BENCHMARK_CONTEST_FILE:-}" build_inline_contest)"
        contest_label="${BENCHMARK_CONTEST:-inline ${BENCHMARK_CONTESTANT_NAME:-${AGENT_TYPE}_dwb}}"
        if [ "$START_AI_CONTROLLER" = "1" ] && [ "$AGENT_TYPE" != "none" ] && [ -n "${BENCHMARK_CONTEST:-}" ]; then
            echo "[WARN] BENCHMARK_CONTEST=$BENCHMARK_CONTEST may contain multiple contestants, but only AGENT_TYPE=$AGENT_TYPE is launched."
            echo "[WARN] Use AGENT_TYPE=all to run socialnav, urbannav, and lelan sequentially with matching single-agent contests."
        fi
    fi

    echo ""
    echo "[INFO] ===== Arena AI benchmark agent: $AGENT_TYPE ====="
    start_ai_sidecars
    start_rviz_sidecar
    run_benchmark_command "$contest_arg" "$contest_label"
    stop_ai_sidecars
}

mkdir -p "$BENCHMARK_DATA_ROOT"

if [ "$AGENT_TYPE" = "all" ]; then
    AI_AGENT_SEQUENCE="${AI_AGENT_SEQUENCE:-socialnav,urbannav,lelan}"
    IFS=',' read -r -a AGENTS_TO_RUN <<< "$AI_AGENT_SEQUENCE"
    for agent in "${AGENTS_TO_RUN[@]}"; do
        agent="$(printf '%s' "$agent" | xargs)"
        if [ -z "$agent" ]; then
            continue
        fi
        run_single_agent_benchmark "$agent" 1
    done
else
    run_single_agent_benchmark "$AGENT_TYPE" 0
fi
