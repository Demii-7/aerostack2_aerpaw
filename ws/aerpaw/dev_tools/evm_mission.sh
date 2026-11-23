#!/bin/bash
# Start the AERPAW mission (waits for the safety pilot to arm) in screen "vehicle".
REPO=/root/aerostack2_aerpaw; PD=$REPO/ws/project_emulator
R=$(readlink -f /root/Results/as2_latest)
screen -S vehicle -X quit >/dev/null 2>&1
screen -S vehicle -dm bash -c "source /opt/ros/humble/setup.bash; source $REPO/ws/install/setup.bash; cd $PD; \
  python3 -u mission_aerpaw.py -n drone0 2>&1 | tee $R/as2_mission.log"
sleep 20
echo "== mission"; tail -5 $R/as2_mission.log
