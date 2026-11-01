#!/bin/bash
# Start MAVROS + Aerostack2 (as2_platform_mavlink) for one emulated AERPAW UAV.
# Run inside the as2 container (started with --network container:E-VM-X0841-M1).
#   ./launch_as2.bash            start, namespace drone0
#   ./launch_as2.bash -n drone1  other namespace
#   ./launch_as2.bash -k         kill the tmux session
# Attach with: tmux attach -t as2_<namespace>

ns="drone0"
kill_only="false"
while getopts "n:k" opt; do
  case ${opt} in
    n ) ns="${OPTARG}" ;;
    k ) kill_only="true" ;;
    * ) echo "usage: $0 [-n namespace] [-k]"; exit 1 ;;
  esac
done

session="as2_${ns}"
tmux kill-session -t "${session}" 2>/dev/null
[[ ${kill_only} == "true" ]] && exit 0

here="$(cd "$(dirname "$0")" && pwd)"
cfg="${here}/config/config.yaml"
src="source /opt/ros/humble/setup.bash; source /root/ws/install/setup.bash; cd ${here}"

windows=(
  "mavros|ros2 launch as2_platform_mavlink mavros_launch.py namespace:=${ns} autopilot:=ardupilot mavros_config_file:=${cfg}"
  "platform|sleep 5; ros2 launch as2_platform_mavlink as2_platform_mavlink_launch.py namespace:=${ns} platform_config_file:=${cfg}"
  "estimator|sleep 7; ros2 launch as2_state_estimator state_estimator_launch.py namespace:=${ns} config_file:=${cfg}"
  "controller|sleep 7; ros2 launch as2_motion_controller controller_launch.py namespace:=${ns} config_file:=${cfg} plugin_name:=pid_speed_controller"
  "behaviors|sleep 9; ros2 launch as2_behaviors_motion motion_behaviors_launch.py namespace:=${ns} config_file:=${cfg}"
  "viewer|sleep 11; ros2 run as2_alphanumeric_viewer as2_alphanumeric_viewer_node --ros-args -r __ns:=/${ns}"
  "mission|echo \"Run: python3 mission_takeoff_land.py -n ${ns}   or   python3 mission_square.py -n ${ns}\""
)

first="true"
for w in "${windows[@]}"; do
  name="${w%%|*}"; cmd="${w#*|}"
  if [[ ${first} == "true" ]]; then
    tmux new-session -d -s "${session}" -n "${name}"
    first="false"
  else
    tmux new-window -t "${session}" -n "${name}"
  fi
  tmux send-keys -t "${session}:${name}" "${src}; ${cmd}" C-m
done

echo "Started tmux session ${session}. Attach: tmux attach -t ${session}"
