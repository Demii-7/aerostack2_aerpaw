#!/bin/bash
R=$(readlink -f /root/Results/as2_latest)
source /opt/ros/humble/setup.bash
echo "== $R"; screen -ls | grep -E "as2|vehicle"
echo "== mavros state"; timeout 6 ros2 topic echo --once /drone0/mavros/state | grep -E "connected|armed|guided|mode"
echo "== rel_alt"; timeout 6 ros2 topic echo --once /drone0/mavros/global_position/rel_alt | grep data
echo "== guard (last)"; grep -v "^.*-> HEARTBEAT" $R/guard.log | tail -${GUARD_LINES:-20}
echo "== platform (last)"; grep -v "Control mode:" $R/as2_platform.log | sed 's/\x1b\[[0-9;]*m//g' | tail -${PLAT_LINES:-20}
echo "== mission"; tail -25 $R/as2_mission.log 2>/dev/null
