#!/bin/bash
# T6: AERPAW mode on the emulator. Run on the Chameleon HOST (not in a container):
#   ~/aerostack2_aerpaw/ws/project_emulator/test_aerpaw_emulator.sh
# Needs: emulator up (E-VM-X0841-M1), as2 container running (docker run -d ... sleep infinity),
# workspace built. Writes ws/notes/tests/T6.*.
#  1. MAVLink audit proxy + stack in AERPAW mode (-a), in screen sessions (-S) as on a real E-VM
#  2. mission_aerpaw.py, which waits for the safety pilot
#  3. simulated safety pilot: the emulator's auto_arm.py arms in STABILIZE (port 14551)
#  4. flight log, flown path and audit report collected

evm="${EVM:-E-VM-X0841-M1}"
as2="${AS2:-as2}"
pd="/root/ws/project_emulator"
out="/root/ws/notes/tests"
in_as2() { docker exec "${as2}" bash -c "source /opt/ros/humble/setup.bash; source /root/ws/install/setup.bash; cd ${pd}; $*"; }

echo "== stop any running stack (vehicle must be landed and disarmed)"
# pkill patterns are anchored so they do not match this bash -c command line itself
in_as2 "./launch_as2.bash -k; ./launch_as2.bash -k -S; pkill -INT -f '^python3 mavlink_audit'; true"
sleep 3

echo "== audit proxy on :14550, MAVROS on :14570, stack in AERPAW mode (screen)"
in_as2 "screen -S as2_audit -dm python3 mavlink_audit.py --listen 14550 --mavros-port 14570 --out ${out}/T6.3_mavlink_audit.json"
in_as2 "RESULTS_DIR=${out} ./launch_as2.bash -a -S -u udp://:14570@127.0.0.1:14550"
sleep 60
in_as2 "screen -ls | grep as2_; grep -h 'AERPAW mode' ${out}/as2_platform.log | head -3"

echo "== mission (waits for pilot) + path recording"
in_as2 "screen -S as2_path -dm bash -c 'ros2 topic echo /drone0/self_localization/pose --csv > ${out}/T6.2_aerpaw_pose.csv'"
in_as2 "date -u +%Y-%m-%dT%H:%M:%SZ > ${out}/T6.2_aerpaw_mission.txt; screen -S as2_mission -dm bash -c 'python3 mission_aerpaw.py -n drone0 >> ${out}/T6.2_aerpaw_mission.txt 2>&1'"
sleep 15

echo "== simulated safety pilot arms (STABILIZE)"
docker exec "${evm}" python3 /opt/standalone/tools/auto_arm.py \
  --connect udp:0.0.0.0:14551 --action arm --mode STABILIZE --timeout 60 2>&1 | tee /tmp/T6.1_pilot_arm.txt

echo "== waiting for the mission to finish (max 10 min)"
for _ in $(seq 120); do
  in_as2 "screen -ls | grep -q as2_mission" || break
  sleep 5
done

in_as2 "screen -S as2_path -X quit; pkill -INT -f '^python3 mavlink_audit'; sleep 3; screen -S as2_audit -X quit; true"
docker cp /tmp/T6.1_pilot_arm.txt "${as2}:${out}/T6.1_pilot_arm.txt"
in_as2 "cat ${out}/T6.2_aerpaw_mission.txt; echo; python3 summarize_aerpaw_path.py ${out}/T6.2_aerpaw_pose.csv | tee ${out}/T6.2_aerpaw_summary.txt; echo; cat ${out}/T6.3_mavlink_audit.json"
in_as2 "grep -h 'AERPAW mode' ${out}/as2_platform.log > ${out}/T6.4_platform_aerpaw_log.txt; ./launch_as2.bash -k -S"
echo "== done; logs in ws/notes/tests/T6.*"
