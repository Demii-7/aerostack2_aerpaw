#!/bin/bash
# Start MAVROS + Aerostack2 (as2_platform_mavlink) for one AERPAW UAV.
# Emulator: run inside the as2 container (started with --network container:E-VM-X0841-M1).
# Real AERPAW E-VM: run natively after aerpaw/install_evm.sh, usually via -a -S.
#   ./launch_as2.bash            start, namespace drone0 (tmux session as2_drone0)
#   ./launch_as2.bash -n drone1  other namespace
#   ./launch_as2.bash -u udp://:14560@ -s 2   other MAVLink link / system ID
#   ./launch_as2.bash -a         AERPAW mode: config_aerpaw.yaml + control_modes_aerpaw.yaml
#   ./launch_as2.bash -S         use screen sessions as2_<ns>_<part> instead of tmux
#                                (AERPAW stopexperiment.sh closes all screen sessions)
#   ./launch_as2.bash -w /path   colcon workspace (default /root/ws)
#   ./launch_as2.bash -k         stop (add -S if it was started with -S)
# Attach with: tmux attach -t as2_<ns>   or   screen -r as2_<ns>_<part>
# With -S and RESULTS_DIR set, each part also logs to $RESULTS_DIR/as2_<part>.log

ns="drone0"
fcu_url="udp://:14550@"  # Stage 1: C-VM mavlink-router -> E-VM UDP 14550
tgt_system="1"
kill_only="false"
aerpaw="false"
use_screen="false"
ws="/root/ws"
while getopts "n:u:s:w:kaS" opt; do
  case ${opt} in
    n ) ns="${OPTARG}" ;;
    u ) fcu_url="${OPTARG}" ;;
    s ) tgt_system="${OPTARG}" ;;
    w ) ws="${OPTARG}" ;;
    k ) kill_only="true" ;;
    a ) aerpaw="true" ;;
    S ) use_screen="true" ;;
    * ) echo "usage: $0 [-n ns] [-u fcu_url] [-s tgt_system] [-w ws] [-a] [-S] [-k]"; exit 1 ;;
  esac
done

session="as2_${ns}"
parts=(mavros platform estimator controller behaviors viewer mission)
if [[ ${use_screen} == "true" ]]; then
  for p in "${parts[@]}"; do screen -S "${session}_${p}" -X quit >/dev/null 2>&1; done
else
  tmux kill-session -t "${session}" 2>/dev/null
fi
[[ ${kill_only} == "true" ]] && exit 0

here="$(cd "$(dirname "$0")" && pwd)"
cfg="${here}/config/config.yaml"
modes_arg=""
mission_hint="python3 mission_takeoff_land.py -n ${ns}   or   python3 mission_square.py -n ${ns}"
if [[ ${aerpaw} == "true" ]]; then
  cfg="${here}/config/config_aerpaw.yaml"
  modes_arg="control_modes_file:=${here}/config/control_modes_aerpaw.yaml"
  mission_hint="python3 mission_aerpaw.py -n ${ns}"
fi
src="source /opt/ros/humble/setup.bash; source ${ws}/install/setup.bash; cd ${here}"

windows=(
  "mavros|ros2 launch as2_platform_mavlink mavros_launch.py namespace:=${ns} autopilot:=ardupilot mavros_config_file:=${cfg} fcu_url:=${fcu_url} tgt_system:=${tgt_system}"
  "platform|sleep 5; ros2 launch as2_platform_mavlink as2_platform_mavlink_launch.py namespace:=${ns} platform_config_file:=${cfg} ${modes_arg}"
  "estimator|sleep 7; ros2 launch as2_state_estimator state_estimator_launch.py namespace:=${ns} config_file:=${cfg}"
  "controller|sleep 7; ros2 launch as2_motion_controller controller_launch.py namespace:=${ns} config_file:=${cfg} plugin_name:=pid_speed_controller"
  "behaviors|sleep 9; ros2 launch as2_behaviors_motion motion_behaviors_launch.py namespace:=${ns} config_file:=${cfg}"
  "viewer|sleep 11; ros2 run as2_alphanumeric_viewer as2_alphanumeric_viewer_node --ros-args -r __ns:=/${ns}"
  "mission|echo \"Run: ${mission_hint}\""
)

first="true"
for w in "${windows[@]}"; do
  name="${w%%|*}"; cmd="${w#*|}"
  if [[ ${use_screen} == "true" ]]; then
    [[ ${name} == "viewer" || ${name} == "mission" ]] && continue  # no terminal to show them
    log="/dev/null"
    [[ -n "${RESULTS_DIR:-}" ]] && log="${RESULTS_DIR}/as2_${name}.log"
    screen -S "${session}_${name}" -dm bash -c "${src}; ${cmd} 2>&1 | tee ${log}"
  elif [[ ${first} == "true" ]]; then
    tmux new-session -d -s "${session}" -n "${name}"
    tmux send-keys -t "${session}:${name}" "${src}; ${cmd}" C-m
    first="false"
  else
    tmux new-window -t "${session}" -n "${name}"
    tmux send-keys -t "${session}:${name}" "${src}; ${cmd}" C-m
  fi
done

if [[ ${use_screen} == "true" ]]; then
  echo "Started screen sessions ${session}_*. List: screen -ls"
else
  echo "Started tmux session ${session}. Attach: tmux attach -t ${session}"
fi
echo "Mode: $([[ ${aerpaw} == "true" ]] && echo AERPAW || echo normal), config ${cfg}"
