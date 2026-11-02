#!/bin/bash
# Stage 5 tests for as2_platform_mavlink on the AERPAW emulator.
# Run inside the as2 container. Each test writes ws/notes/tests/T5.x_*.txt.
#   ./run_tests.bash build      T5.1 build the platform
#   ./run_tests.bash check      T5.2 stack running: MAVROS link, platform info, position
#   ./run_tests.bash takeoff    T5.3 takeoff + land mission (watch QGC)
#   ./run_tests.bash square     T5.4 10 m square mission (watch QGC)
# Start the stack (./launch_as2.bash) before check/takeoff/square.

ns="drone0"
here="$(cd "$(dirname "$0")" && pwd)"
out="/root/ws/notes/tests"
mkdir -p "${out}"
source /opt/ros/humble/setup.bash
[[ -f /root/ws/install/setup.bash ]] && source /root/ws/install/setup.bash

log() {  # log <file> <command...>: run, show, and save output with a UTC header
  local file="${out}/$1"; shift
  { echo "# $(date -u +%Y-%m-%dT%H:%M:%SZ)  $*"; "$@" 2>&1; echo "# exit=$?"; } | tee "${file}"
}

case "$1" in
  build)
    cd /root/ws
    log T5.1_build.txt colcon build --symlink-install --packages-select as2_platform_mavlink \
      --cmake-args -DBUILD_TESTING=OFF
    ;;
  check)
    log T5.2a_mavros_state.txt timeout 10 ros2 topic echo /${ns}/mavros/state --once
    log T5.2b_platform_info.txt timeout 10 ros2 topic echo /${ns}/platform/info --once
    log T5.2c_self_loc.txt timeout 10 ros2 topic echo /${ns}/self_localization/pose --once
    log T5.2d_nodes.txt ros2 node list
    ;;
  takeoff)
    cd "${here}"
    log T5.3_takeoff_land.txt python3 mission_takeoff_land.py -n ${ns}
    ;;
  square)
    cd "${here}"
    log T5.4_square.txt python3 mission_square.py -n ${ns}
    ;;
  *)
    sed -n 2,9p "$0"; exit 1
    ;;
esac
