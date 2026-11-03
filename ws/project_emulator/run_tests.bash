#!/bin/bash
# Stage 5 tests for as2_platform_mavlink on the AERPAW emulator.
# Run inside the as2 container. Each test writes ws/notes/tests/T5.x_*.txt.
#   ./run_tests.bash build      T5.1 build the platform
#   ./run_tests.bash check      T5.2 stack running: MAVROS link, platform info, position
#   ./run_tests.bash reset      T5.0 on the ground: disarm + LAND mode (before each mission)
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
    # A timed-out echo leaves the ros2 CLI daemon broken (!rclpy.ok), so restart it each time
    echo1() { ros2 daemon stop >/dev/null 2>&1; timeout 20 ros2 topic echo "$1" --once; }
    log T5.2a_mavros_state.txt echo1 /${ns}/mavros/state
    log T5.2b_platform_info.txt echo1 /${ns}/platform/info
    log T5.2c_self_loc.txt echo1 /${ns}/self_localization/pose
    log T5.2d_nodes.txt ros2 node list --no-daemon
    ;;
  reset)
    # Back to the start state: disarmed, LAND mode (only safe on the ground).
    # Needed because the AS2 1.1.3 binary fails arm()/offboard() if already armed/GUIDED.
    log T5.0_reset.txt bash -c "ros2 service call /${ns}/mavros/cmd/arming mavros_msgs/srv/CommandBool '{value: false}' && ros2 service call /${ns}/mavros/set_mode mavros_msgs/srv/SetMode '{custom_mode: LAND}'"
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
