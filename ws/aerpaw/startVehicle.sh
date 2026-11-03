#!/bin/bash
# AERPAW vehicle script: Aerostack2 + MAVROS in AERPAW mode, then the mission.
# Install on the E-VM as /root/Profiles/ProfileScripts/Vehicle/startVehicle.sh and
# uncomment ./Vehicle/startVehicle.sh in /root/startexperiment.sh. AERPAW runs
# startexperiment.sh (you in Development mode, the operators in Testbed mode);
# stopexperiment.sh closes every screen session, which stops all of this.
#
# Same layout as the AERPAW samples (Samples/startPreplannedTrajectory.sh):
# a screen session per process, output logged to $RESULTS_DIR.
# The vehicle MAVLink stream reaches the E-VM on UDP 14550 (as for aerpawlib --conn :14550).

REPO="${AS2_REPO:-/root/aerostack2_aerpaw}"
PD="${REPO}/ws/project_emulator"
RESULTS_DIR="${RESULTS_DIR:-/root/Results}"
mkdir -p "${RESULTS_DIR}"
export RESULTS_DIR

# Stack in AERPAW mode, screen sessions as2_drone0_*
"${PD}/launch_as2.bash" -a -S -w "${REPO}/ws" -u "udp://:14550@" -s 1

# Optional: record what we send to the autopilot (MAVROS then binds 14570), e.g. for
# the first Development-mode run, to compare with the MAVLink filter rules:
#   screen -S as2_audit -dm python3 "${PD}/mavlink_audit.py" --out "${RESULTS_DIR}/mavlink_audit.json"
#   "${PD}/launch_as2.bash" -a -S -w "${REPO}/ws" -u "udp://:14570@127.0.0.1:14550" -s 1

# Mission after the stack is up; it waits for the safety pilot to arm.
screen -S vehicle -dm bash -c "sleep 60; source /opt/ros/humble/setup.bash; \
  source ${REPO}/ws/install/setup.bash; cd ${PD}; \
  python3 mission_aerpaw.py -n drone0 2>&1 | tee ${RESULTS_DIR}/as2_mission.log"
