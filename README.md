# Arena AI Integration

`arena_ai_integration` is the Arena ROS 2 package that runs external AI
navigation policies as Nav2-compatible controllers. In this workspace it is
used to connect SocialNav, UrbanNav, and LeLaN model inference to Arena/Nav2
DWB benchmark runs.

The package is intentionally self-contained: controller nodes, agent wrappers,
model runtime code, checkpoints, launch files, scripts, and benchmark helper
configs all live under:

```text
/home/khanhtoan/arena_ws/src/Arena/arena_ai_integration
```

When running inside the Arena Docker container, the same workspace is normally
mounted at:

```text
/opt/arena_ws
```

Most scripts default to `/opt/arena_ws`, but they also respect
`WORKSPACE_DIR`/`ARENA_WS_DIR`.

## What This Package Provides

Runtime entry points installed by `setup.py`:

```text
ai_controller
human_states_bridge
semantic_laser_filter
aggregate_benchmark_metrics
```

Main launch file:

```text
launch/ai_controller.launch.py
```

Agent-specific parameter files:

```text
config/base_params.yaml
config/socialnav_params.yaml
config/urbannav_params.yaml
config/lelan_params.yaml
```

Model config files:

```text
config/models/socialnav_film.yaml
config/models/urbannav_film.yaml
config/models/lelan.yaml
```

Bundled checkpoints:

```text
checkpoints/SocialNav_1_path.pth
checkpoints/SocialNav_margin_last.pth
checkpoints/UrbanNav_FiLM.pth
checkpoints/LeLan_latest.pth
```

## Runtime Architecture

The controller receives Arena/Nav2 state, runs an AI agent, converts model
waypoints into ROS coordinates, and sends a path to Nav2 `FollowPath`.

```text
RGB image history + odom + global goal + instruction
  -> arena_ai_integration.nodes.ai_controller_node
  -> SocialNavAgent | UrbanNavAgent | LeLanAgent
  -> local AI waypoints + arrival score
  -> BaseAINode path adapter
  -> Nav2 ComputePathToPose / FollowPath
  -> DWB cmd_vel_nav
  -> robot cmd_vel
```

The default integration mode is:

```text
ARENA_AI_DWB_INTEGRATION=path_adapter
```

Supported `dwb_integration_mode` values are:

```text
none
path_adapter
shaped_path
shaped_path_no_tail
one_waypoint_replace
hard_gate
```

`use_dwb_hard_gate:=true` forces `hard_gate` mode. Normal benchmark runs should
prefer `path_adapter` unless testing another integration mode explicitly.

## Supported Agents

| `AGENT_TYPE` | Params file | Model config | Default checkpoint |
| --- | --- | --- | --- |
| `socialnav` | `socialnav_params.yaml` | `socialnav_film.yaml` | `SocialNav_1_path.pth` |
| `urbannav` | `urbannav_params.yaml` | `urbannav_film.yaml` | `UrbanNav_FiLM.pth` |
| `lelan` | `lelan_params.yaml` | `lelan.yaml` | `LeLan_latest.pth` |

The agent type selects the Python wrapper:

```text
socialnav -> arena_ai_integration.agents.socialnav_agent.SocialNavAgent
urbannav  -> arena_ai_integration.agents.urbannav_agent.UrbanNavAgent
lelan     -> arena_ai_integration.agents.lelan_agent.LeLanAgent
```

`agent_name` is passed to the controller and is also used by the agent helper
when looking for a matching `checkpoints/<agent_name>.pth`.

## Build

From the host workspace, enter the Arena shell/container first:

```bash
cd /home/khanhtoan/arena_ws
source arena
```

Then build the package from the Arena shell. The workspace path inside the
container is usually `/opt/arena_ws`:

```bash
cd /opt/arena_ws
source /opt/arena_ws/source
arena build --packages-select arena_ai_integration
source install/setup.bash
```

This scoped build only rebuilds `arena_ai_integration` artifacts under
`build/`, `install/`, and `log/`. It does not edit source files or rebuild other
packages unless the build tool is invoked with a broader package selection.

If you need to build directly with colcon:

```bash
colcon build --packages-select arena_ai_integration --symlink-install
source install/setup.bash
```

If you are already in a locally sourced Arena shell that uses the host path,
replace `/opt/arena_ws` with `/home/khanhtoan/arena_ws`.

## Run A Standalone Agent Session

Use `start_agent.sh` to launch Arena plus one AI controller:

```bash
cd /home/khanhtoan/arena_ws
WORKSPACE_DIR=/home/khanhtoan/arena_ws \
AGENT_TYPE=socialnav \
ARENA_AI_DWB_INTEGRATION=path_adapter \
bash src/Arena/arena_ai_integration/scripts/start_agent.sh
```

Other agents:

```bash
AGENT_TYPE=urbannav bash src/Arena/arena_ai_integration/scripts/start_agent.sh
AGENT_TYPE=lelan bash src/Arena/arena_ai_integration/scripts/start_agent.sh
```

Useful overrides:

```text
SIM=isaac
WORLD=hospital_1
ROBOT=turtlebot
LOCAL_PLANNER=dwb
GLOBAL_PLANNER=navfn
INTER_PLANNER=default
ARENA_HEADLESS=1
ENABLE_VISUALIZATION=false
MODEL_CONFIG=/path/to/model.yaml
MODEL_CHECKPOINT=/path/to/checkpoint.pth
```

For `socialnav`, the script also starts:

```text
human_states_bridge
semantic_laser_filter
```

## Run Benchmarks

Before long Isaac/Arena benchmark runs, make sure the host has enough inotify
capacity:

```bash
sudo sysctl -w fs.inotify.max_user_watches=524288
sudo sysctl -w fs.inotify.max_user_instances=1024
sudo sysctl -w fs.inotify.max_queued_events=32768
```

Default single-agent benchmark:

```bash
cd /home/khanhtoan/arena_ws
WORKSPACE_DIR=/home/khanhtoan/arena_ws \
AGENT_TYPE=socialnav \
BENCHMARK_SCENARIOS=default \
BENCHMARK_EPISODES=1 \
ARENA_HEADLESS=1 \
bash src/Arena/arena_ai_integration/scripts/start_benchmark.sh
```

Run without auto-activating the default `socialnav` conda environment:

```bash
BENCHMARK_CONDA_ENV=none \
bash src/Arena/arena_ai_integration/scripts/start_benchmark.sh
```

If conda is installed in a non-standard location:

```bash
BENCHMARK_CONDA_SH=/path/to/etc/profile.d/conda.sh \
bash src/Arena/arena_ai_integration/scripts/start_benchmark.sh
```

Run all bundled AI agents sequentially:

```bash
AGENT_TYPE=all \
AI_AGENT_SEQUENCE=socialnav,urbannav,lelan \
ARENA_HEADLESS=1 \
bash src/Arena/arena_ai_integration/scripts/start_benchmark.sh
```

Run a pure DWB baseline without an AI controller:

```bash
AGENT_TYPE=none \
START_AI_CONTROLLER=0 \
BENCHMARK_CONTEST_FILE=src/Arena/arena_ai_integration/config/benchmark/contests/dwb_baseline.yaml \
bash src/Arena/arena_ai_integration/scripts/start_benchmark.sh
```

Benchmark helper configs are available at:

```text
config/benchmark/suites/hospital_1_default.yaml
config/benchmark/contests/socialnav_dwb.yaml
config/benchmark/contests/dwb_baseline.yaml
```

Without `BENCHMARK_SUITE`, `BENCHMARK_SUITE_FILE`, `BENCHMARK_CONTEST`, or
`BENCHMARK_CONTEST_FILE`, `start_benchmark.sh` builds inline suite/contest JSON
from the environment variables.

Benchmark outputs default to:

```text
data/benchmarks
data/benchmarks/arena_ai_sidecars
```

## Data Recorder Helper

`start_data_recorder.sh` orchestrates baseline Arena data collection. It can
prepare scenarios, launch Arena, start ground-truth bbox helpers, run the
recorder, and repeat episodes.

Example:

```bash
cd /home/khanhtoan/arena_ws
WORKSPACE_DIR=/home/khanhtoan/arena_ws \
SCENARIOS=default_05,default_04 \
EPISODES=1 \
RUN_DURATION=180 \
LOCAL_PLANNER=dwb \
RUN_ID_START=2000 \
bash src/Arena/arena_ai_integration/scripts/start_data_recorder.sh
```

Common recorder commands:

```bash
bash src/Arena/arena_ai_integration/scripts/start_data_recorder.sh status
bash src/Arena/arena_ai_integration/scripts/start_data_recorder.sh stop
```

## Direct ROS Launch

After building and sourcing the workspace:

```bash
ros2 launch arena_ai_integration ai_controller.launch.py \
  agent_type:=socialnav \
  params_file:="$(ros2 pkg prefix arena_ai_integration)/share/arena_ai_integration/config/socialnav_params.yaml" \
  agent_name:=socialnav \
  model_config_path:=/home/khanhtoan/arena_ws/src/Arena/arena_ai_integration/config/models/socialnav_film.yaml \
  model_checkpoint_path:=/home/khanhtoan/arena_ws/src/Arena/arena_ai_integration/checkpoints/SocialNav_1_path.pth \
  robot_namespace:=/arena/env_0/task_generator_node/turtlebot \
  robot_frame:=turtlebot/base_link \
  image_topic:=/arena/env_0/task_generator_node/turtlebot/rgbd_camera/image \
  dwb_cmd_topic:=/arena/env_0/task_generator_node/turtlebot/cmd_vel_nav \
  cmd_vel_topic:=/arena/env_0/task_generator_node/turtlebot/cmd_vel \
  plan_topic:=/arena/env_0/task_generator_node/turtlebot/plan \
  dwb_integration_mode:=path_adapter \
  use_sim_time:=true
```

Use the `/opt/arena_ws/...` path variants for the model files when launching
inside the Arena container.

## Important Runtime Notes

Only one `arena_ai_integration` controller should run for a given robot
namespace. Running multiple external controllers against the same robot can
cause conflicting `cmd_vel` behavior.

The AI model dependencies are separate from the ROS package metadata. If model
loading fails, verify the active Python/conda environment, CUDA/PyTorch
availability, model config path, and checkpoint path.

`SocialNavAgent` can soft-fail into DWB fallback mode when the model cannot be
loaded. UrbanNav and LeLaN expect their configs and checkpoints to exist.

The default Arena robot namespace differs between launch paths:

```text
start_agent.sh default:      /task_generator_node/turtlebot
start_benchmark.sh default:  /arena/env_0/task_generator_node/turtlebot
```

Override `ARENA_AI_ROBOT_NAMESPACE`, `ARENA_AI_ROBOT_FRAME`, and topic variables
when `ros2 topic list` shows a different namespace layout.
