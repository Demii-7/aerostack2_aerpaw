#!/bin/bash
# Start guard proxy + Aerostack2 (AERPAW mode) on the E-VM, then report link state.
REPO=/root/aerostack2_aerpaw; PD=$REPO/ws/project_emulator
export RESULTS_DIR=/root/Results/as2_$(date -u +%m%d_%H%M); mkdir -p $RESULTS_DIR
echo "results: $RESULTS_DIR"; ln -sfn $RESULTS_DIR /root/Results/as2_latest
$PD/launch_as2.bash -k -S >/dev/null 2>&1; screen -S as2_guard -X quit >/dev/null 2>&1; screen -S vehicle -X quit >/dev/null 2>&1
pkill -f mavros_node; pkill -f as2_; sleep 2
screen -S as2_guard -dm bash -c "python3 $PD/aerpaw_filter_guard.py --listen 14550 --mavros-port 14570 --log $RESULTS_DIR/guard.log --geofence /root/AERPAW-Dev/AHN/C-VM/MAVLink_Filter/Geofences/copter_geofence.kml"
sleep 1
$PD/launch_as2.bash -a -S -w $REPO/ws -u udp://:14570@127.0.0.1:14550 -s 1
sleep 45
source /opt/ros/humble/setup.bash; source $REPO/ws/install/setup.bash
echo "== screens"; screen -ls | grep -E "as2|vehicle"
echo "== mavros state"; timeout 8 ros2 topic echo --once /drone0/mavros/state | head -12
echo "== platform info"; timeout 8 ros2 topic echo --once /drone0/platform/info | head -20
echo "== gps"; timeout 8 ros2 topic echo --once /drone0/mavros/global_position/global | grep -E "latitude|longitude|altitude"
echo "== guard log"; tail -25 $RESULTS_DIR/guard.log
echo "== mavros log (plugins / errors)"; grep -E "Plugin|plugin|ERROR|WARN|AERPAW" $RESULTS_DIR/as2_mavros.log | tail -20
echo "== platform log"; tail -15 $RESULTS_DIR/as2_platform.log
echo "== streams"; tail -5 $RESULTS_DIR/as2_streams.log
