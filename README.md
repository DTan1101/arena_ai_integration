# Arena AI Integration

Unified ROS 2 integration for AI navigation agents in Arena.

## Architecture

`arena_ai_integration` owns the AI-DWB runtime for SocialNav, UrbanNav, and
LeLaN benchmark runs. Model inference code, ROS sidecars, and benchmark helpers
are packaged inside this ROS 2 package.

Runtime flow:

```text
RGB / odom / goal / instruction
  -> arena_ai_integration.nodes.ai_controller_node
  -> SocialNavAgent | UrbanNavAgent | LeLanAgent
  -> local waypoints + arrival score
  -> BaseAINode FollowPath path-adapter
  -> Nav2 DWB FollowPath
  -> cmd_vel_nav_raw relay to cmd_vel
```

With `ARENA_AI_DWB_INTEGRATION=shaped_path`, Nav2 still computes the benchmark
global path to the final goal. The AI controller inserts the leading AI
waypoints into the start of that path, rejoins the global path ahead of the
robot, and sends the result as a `nav_msgs/Path` through Nav2 `FollowPath`.
The raw AI output is never sent directly to DWB.

With `ARENA_AI_DWB_INTEGRATION=one_waypoint_replace`, Nav2 computes the same
benchmark global path, but the controller replaces only the selected waypoint
ahead of the robot (`path_waypoint_index`, default fourth waypoint) with the
matching AI waypoint before sending the path to DWB.

UrbanNav and LeLaN use the same FollowPath path-adapter as SocialNav. The old
hard-gate DWB candidate selection and waypoint-regeneration logic is intentionally
not used by the unified controller.

## Checkpoints

Place model weights here:

```text
arena_ai_integration/checkpoints/
  SocialNav_1_path.pth
  UrbanNav_FiLM.pth
  LeLan_latest.pth
```

The model YAML files are installed from:

```text
arena_ai_integration/config/models/
  socialnav_film.yaml
  urbannav_film.yaml
  lelan.yaml
```

## Agents

| agent_type | Default checkpoint | Runtime module |
| --- | --- | --- |
| `socialnav` | `SocialNav_1_path.pth` | `arena_ai_integration.models.socialnav.runtime.SocialNavModel` |
| `urbannav` | `UrbanNav_FiLM.pth` | `arena_ai_integration.models.socialnav.runtime.UrbanNavModel` |
| `lelan` | `LeLan_latest.pth` | `arena_ai_integration.models.lelan.runtime.LeLaNInferenceModel` |

`agent_name` still selects the checkpoint name when a matching
`checkpoints/<agent_name>.pth` exists. `agent_type` selects the wrapper class.

## Build

```bash
cd /opt/arena_ws
colcon build --packages-select arena_ai_integration --symlink-install
source install/setup.bash
```

## Run

Standalone controller:

```bash
sudo sysctl -w fs.inotify.max_user_watches=524288
sudo sysctl -w fs.inotify.max_user_instances=1024
sudo sysctl -w fs.inotify.max_queued_events=32768

source /opt/arena_ws/source
source /opt/arena_ws/install/setup.bash
conda activate socialnav

ARENA_AI_DWB_INTEGRATION=shaped_path_no_tail ARENA_AI_PYTHONNOUSERSITE=1 ARENA_HEADLESS=1 bash ./src/Arena/arena_ai_integration/scripts/start_benchmark.sh

AGENT_TYPE=socialnav ./src/Arena/arena_ai_integration/scripts/start_agent.sh
AGENT_TYPE=urbannav ./src/Arena/arena_ai_integration/scripts/start_agent.sh
AGENT_TYPE=lelan ./src/Arena/arena_ai_integration/scripts/start_agent.sh

SCENARIOS=default_05,default_04,moving_peds EPISODES=1 RUN_DURATION=180 LOCAL_PLANNER=mppi RUN_ID_START=2000 ./src/Arena/arena_ai_integration/scripts/start_data_recorder.sh
```

`start_benchmark.sh` activates `BENCHMARK_CONDA_ENV=socialnav` by default before
starting the AI controller. If conda is installed outside the usual
`~/miniconda3`, `~/anaconda3`, `/opt/conda`, or miniforge/mambaforge paths, pass
the init script explicitly:

```bash
BENCHMARK_CONDA_SH=/path/to/etc/profile.d/conda.sh bash ./src/Arena/arena_ai_integration/scripts/start_benchmark.sh
```

If the current python environment already contains the AI dependencies, disable
auto-activation:

```bash
BENCHMARK_CONDA_ENV=none bash ./src/Arena/arena_ai_integration/scripts/start_benchmark.sh
```

To run all bundled AI agents sequentially over the same suite, use
`AGENT_TYPE=all`. The script runs `socialnav`, `urbannav`, then `lelan`, each
with a matching single-agent DWB contestant so the external AI controller and
benchmark contestant stay aligned:

```bash
BENCHMARK_CONDA_ENV=none \
BENCHMARK_SUITE=social_contest \
AGENT_TYPE=all \
ARENA_HEADLESS=1 \
bash ./src/Arena/arena_ai_integration/scripts/start_benchmark.sh
```

`start_benchmark.sh` does not launch RViz unless requested. To inspect a run on
a machine/container with display forwarding:

```bash
START_RVIZ=1 ARENA_HEADLESS=0 bash ./src/Arena/arena_ai_integration/scripts/start_benchmark.sh
```

RViz is launched through Arena's `rviz_utils` attach flow, the same path used by
`arena viz`. It defaults to `RVIZ_NS=/arena/env_0/task_generator_node`,
`RVIZ_VIEW=map`, and `RVIZ_ROBOT=0`.

Benchmark runs use `arena_simulation_setup/launch/robot.launch.py` to map:

```text
SocialNav*      -> agent_type=socialnav
UrbanNav*       -> agent_type=urbannav
LeLan* / LeLaN* -> agent_type=lelan
```

Pure DWB baselines should use an empty/non-AI `agent_name`, so no AI controller is
launched.

Runtime modules:

```text
python3 -m arena_ai_integration.nodes.ai_controller_node
python3 -m arena_ai_integration.nodes.human_states_bridge
python3 -m arena_ai_integration.nodes.semantic_laser_filter
python3 -m arena_ai_integration.tools.aggregate_benchmark_metrics
```

## Benchmark Configs

`start_benchmark.sh` follows Arena's current benchmark layout. It calls:

```bash
ros2 run arena_evaluation benchmark --suite <suite> --contest <contest>
```

By default the script builds inline YAML equivalent to:

```text
arena_ai_integration/config/benchmark/
  suites/hospital_1_default.yaml
  contests/socialnav_dwb.yaml
```

Useful overrides:

```bash
BENCHMARK_SCENARIOS=default,normal BENCHMARK_EPISODES=1 bash ./src/Arena/arena_ai_integration/scripts/start_benchmark.sh
BENCHMARK_SUITE=basic BENCHMARK_CONTEST=basic AGENT_TYPE=none START_AI_CONTROLLER=0 bash ./src/Arena/arena_ai_integration/scripts/start_benchmark.sh
BENCHMARK_SUITE_FILE=./src/Arena/arena_ai_integration/config/benchmark/suites/hospital_1_default.yaml \
BENCHMARK_CONTEST_FILE=./src/Arena/arena_ai_integration/config/benchmark/contests/socialnav_dwb.yaml \
bash ./src/Arena/arena_ai_integration/scripts/start_benchmark.sh
```

## Conflict Rule

Only one AI controller should run for a robot namespace. Do not launch
additional external controllers together with `arena_ai_integration` for the same
robot namespace.
