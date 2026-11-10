# Documentation (newest first)

Platform code: `ws/src/as2_platform_mavlink` is a git submodule of https://github.com/Demii-7/as2_platform_mavlink
(fork of aerostack2/as2_platform_mavlink, branch `aerpaw`: 1.1.0 + ArduPilot support from GQP3715/AS2_ardupilot
+ our fixes and AERPAW mode). This repo keeps everything else (configs, missions, scripts, notes).
Clone with `git clone --recurse-submodules ...`, or run `git submodule update --init` after a pull or checkout.
To change the platform: commit inside ws/src/as2_platform_mavlink, push to the fork, then commit the new submodule commit here.

## Stage 7 results: first real AERPAW Development session (Nov 10, 2026)

Goal: get our Aerostack2 stack talking to the drone from a real AERPAW E-VM.

What I did:
- Experiment as2_aerpaw_demarce2 (ID 1600), one UAV node (LPN1), Development. (1599 dropped: AERPAW only installs
  SSH keys that are in the profile at the first Initiate Development.)
- `ssh -i ~/.ssh/id_aerpaw_rsa root@192.168.122.1` (VPN on). E-VM: Ubuntu 22.04.5, internet works.
- Docker on the E-VM: not possible (below).
- Native install, then Save in the portal: `git clone --recurse-submodules https://github.com/Demii-7/aerostack2_aerpaw.git /root/aerostack2_aerpaw`,
  checkout stage5-pivot-mavlink-platform, `git submodule update --init`, `bash ./ws/aerpaw/install_evm.sh` (platform built in 34 s).
- MAVROS on UDP 14550 (the port AERPAW's own scripts use): saw the drone for a moment, then nothing.

Results:
- E-VM side works: install, build, network to the C-VM and the OEO console.
- No flight yet. MAVROS sent messages the MAVLink filter does not allow (SYSTEM_TIME, TIMESYNC); any disallowed
  message makes the filter put the drone in LOITER and shut down, so nothing reaches the E-VM afterwards.
- Filter rules read from AERPAW's C-VM code (ws/notes/aerpaw_filter_findings_2026-11-10.md). AERPAW mode needs:
  MAVROS sending only allowed messages; mode changes as DO_SET_MODE (176), not SET_MODE; waypoints as
  DO_REPOSITION (192), not position targets in SET_POSITION_TARGET_GLOBAL_INT (velocity only).

Next: make the three changes, rehearse on Chameleon with AERPAW's real filter, restart the Development session, fly the square.

Answers to the Nov 3 meeting questions:
1. Can docker run be executed in an AERPAW E-VM? No: the E-VM is an unprivileged container, every container fails
   with "unshare: operation not permitted". install_evm.sh installs the same packages natively instead.
2. Why would an experimenter run an AERPAW experiment with Aerostack2? What Aerostack2 adds to AERPAW:
   - Cross-platform portability: Develop autonomy missions that can transfer across simulation environments, AERPAW, and other supported drone platforms.
   - Complete autonomy stack: Ready-made state estimation, motion control, path planning, behaviors, and mission execution.
   - Communication-aware autonomy: Integrate AERPAW's wireless measurements into autonomous navigation and decision-making.
   - Multi-UAV coordination: Support research into formation control, leader-follower systems, consensus, and distributed planning.
   - Experiment recording and analysis: Record synchronized vehicle states, commands, sensor data, and wireless measurements using ROS bags.
   - Flight reconstruction and simulation replay: Reconstruct real-world flights in RViz and replay recorded commands in Gazebo to investigate failures and test improvements.
   - Reusable research infrastructure: Develop and evaluate custom autonomy and coordination algorithms without repeatedly rebuilding the underlying robotics architecture.
   - Integration costs and limitations: Additional computational overhead, ROS 2 integration, communication latency, and command-interface restrictions that require evaluation.
3. What does it take to implement planning and coordination algorithms in Aerostack2? What we need to set up, and how it works:
   - One Aerostack2 stack per drone: each drone's E-VM runs MAVROS, our platform in AERPAW mode, the state estimator, the controller and the motion behaviors, in its own namespace (drone0, drone1, ...); today's single-drone setup repeated on every E-VM.
   - A shared ROS 2 network: all E-VMs use the same ROS_DOMAIN_ID so each drone's topics and behaviors are visible to the others over AERPAW's experiment network; a Fast DDS discovery server on one E-VM if multicast is blocked. Not tested yet.
   - One common map: each drone measures position from its own takeoff point, so the coordinator converts every drone to one shared frame using GPS.
   - The algorithm as a coordinator: a Python mission with one drone interface per drone (fastest) or a custom Aerostack2 behavior (reusable), on one E-VM. Each step it reads all drones' positions, computes each drone's next target (leader-follower offset, consensus average, coverage cell) and sends it through that drone's go_to behavior. A distributed version runs one copy per drone reading its neighbours' positions.
   - Commands through AERPAW's rules: go_to becomes a GPS waypoint (DO_REPOSITION, after the planned fix) that the filter checks against the geofence; the safety pilot arms each drone. Algorithms advance in waypoint steps every 1 to 2 s; velocity commands are also allowed by the filter if we enable them in AERPAW mode.
   - Safety and measurement: a minimum-separation check before sending targets; rosbag2 records every drone's position, target and timing for formation error, minimum separation and completion time.
   - Test path: Aerostack2's simulator or Gazebo with several drones, then the two-drone AERPAW emulator, then AERPAW Development, then the testbed. None of the multi-drone pieces are built yet; one drone flying on AERPAW comes first.
4. Implement, then run on AERPAW: in progress; one drone must fly on AERPAW first (needs the three fixes).

## Stage 6: AERPAW mode, flying by the real AERPAW rules (Nov 3, 2026)

Why: on real AERPAW a MAVLink filter between the E-VM and the drone only allows GUIDED and LAND, takeoff to 20–110 m
and GPS waypoints; the safety pilot arms; the drone must land within 5 m of takeoff. Our emulator has no filter, so
Stage 5 (5 m, our own arm command, 50 Hz local setpoints) would abort on AERPAW. Research and plan:
ws/notes/aerpaw_real_testbed_plan.md.

Code change: parameter aerpaw.enabled in as2_platform_mavlink (src/aerpaw_mode.cpp): waits for the pilot to arm, one
GPS waypoint per move, refuses < 20 m or > 110 m, LAND only within 5 m of takeoff. Settings: config/config_aerpaw.yaml
(takeoff 25 m), config/control_modes_aerpaw.yaml (HOVER and POSITION only).

| Action | Window | Command | Result |
|---|---|---|---|
| Get the latest code | W2 | cd ~/aerostack2_aerpaw; git pull; git submodule update --init | |
| Start the as2 container | W3 | docker run -it --rm --name as2 --network container:E-VM-X0841-M1 -v ~/aerostack2_aerpaw/ws:/root/ws as2-aerpaw bash | |
| Rebuild the platform | W3 | cd /root/ws; colcon build --symlink-install --packages-select as2_platform_mavlink --cmake-args -DBUILD_TESTING=OFF; source install/setup.bash | 1 package finished |
| Start MAVROS, connected to the drone on UDP 14550 | W3 | ros2 launch as2_platform_mavlink mavros_launch.py namespace:=drone0 autopilot:=ardupilot fcu_url:=udp://:14550@ tgt_system:=1 mavros_config_file:=/root/ws/project_emulator/config/config_aerpaw.yaml | |
| New container shell (W4–W8), workspace loaded | W4–W8 | ssh chameleon; docker exec -it as2 bash -c "source /root/ws/install/setup.bash && exec bash" | (if you type the source line separately, wait for the root@e-vm prompt first, or ROS reports "Package 'as2_platform_mavlink' not found") |
| Platform (Aerostack2 commands → MAVROS) | W4 | ros2 launch as2_platform_mavlink as2_platform_mavlink_launch.py namespace:=drone0 platform_config_file:=/root/ws/project_emulator/config/config_aerpaw.yaml control_modes_file:=/root/ws/project_emulator/config/control_modes_aerpaw.yaml | |
| State estimator (position in earth frame) | W5 | ros2 launch as2_state_estimator state_estimator_launch.py namespace:=drone0 config_file:=/root/ws/project_emulator/config/config_aerpaw.yaml | |
| Motion controller | W6 | ros2 launch as2_motion_controller controller_launch.py namespace:=drone0 config_file:=/root/ws/project_emulator/config/config_aerpaw.yaml plugin_name:=pid_speed_controller | |
| Motion behaviors (takeoff, land, go_to) | W7 | ros2 launch as2_behaviors_motion motion_behaviors_launch.py namespace:=drone0 config_file:=/root/ws/project_emulator/config/config_aerpaw.yaml | |
| Check AERPAW mode is on | W4 | (read the output) | "AERPAW mode: pilot arms, GUIDED/LAND only, global waypoints, altitude 20-110 m" |
| Start the mission | W8 | cd /root/ws/project_emulator; python3 mission_aerpaw.py -n drone0 | "waiting for the safety pilot to arm..." |
| Act as the safety pilot (arm in STABILIZE) | W2 | docker exec E-VM-X0841-M1 python3 /opt/standalone/tools/auto_arm.py --connect udp:0.0.0.0:14551 --action arm --mode STABILIZE --timeout 60 | vehicle armed |
| Watch the flight | W8, QGC | | arm OK, GUIDED, takeoff 25 m, 20 m square, back over takeoff point, LAND |
| Optional: record every MAVLink message we send (start before MAVROS; MAVROS then uses fcu_url:=udp://:14570@127.0.0.1:14550) | W9 | python3 /root/ws/project_emulator/mavlink_audit.py --listen 14550 --mavros-port 14570 --out /root/ws/notes/tests/T6.3_mavlink_audit.json | JSON summary on Ctrl+C |
| Stop | all | Ctrl+C in each window | |

Results:
- Run 1: takeoff refused, "no GPS fix" (the Stage 5 namespace fix changed the GPS topic). Fixed: platform also reads /drone0/mavros/global_position/global.
- Run 2: waited for the pilot, takeoff 24.9 m, 20 m square at 22.5 m, landed 0.05 m from takeoff.
- Audit: no arm/disarm sent; 1 NAV_TAKEOFF, SET_MODE GUIDED and LAND, 19 SET_POSITION_TARGET_GLOBAL_INT + MAVROS housekeeping.
- aerpawlib demo_square through the same audit: waypoints as MISSION_ITEM current=2, mode via DO_SET_MODE.
  Open question: does the real filter accept SET_POSITION_TARGET_GLOBAL_INT?

Shortcut: ws/project_emulator/test_aerpaw_emulator.sh runs the same commands in screen sessions; logs in ws/notes/tests/T6.*.

✅ Stage 6 complete on the emulator.

## Stage 5 (pivot): use as2_platform_mavlink instead of our own platform (Nov 2, 2026)

Why: meeting Oct 20, 2026. Every job left in our plan (stages 5–8) already exists in as2_platform_mavlink with the
ArduPilot changes from https://github.com/GQP3715/AS2_ardupilot (commit dea4310). Comparison: ws/notes/platform_comparison.md.
Our own as2_platform_aerpaw is kept for reference; its stage 5 WIP is on branch stage5-aerpaw-platform-wip.

| Action | Window | Command | Result |
|---|---|---|---|
| Get the branch | W2 | cd ~/aerostack2_aerpaw; git fetch; git checkout stage5-pivot-mavlink-platform; git submodule update --init | |
| Start the as2 container | W3 | docker run -it --rm --name as2 --network container:E-VM-X0841-M1 -v ~/aerostack2_aerpaw/ws:/root/ws as2-aerpaw bash | |
| Build the platform | W3 | cd /root/ws; colcon build --symlink-install --packages-select as2_platform_mavlink --cmake-args -DBUILD_TESTING=OFF; source install/setup.bash | 1 package finished (52.4 s) |
| Start MAVROS, connected to the drone on UDP 14550 | W3 | ros2 launch as2_platform_mavlink mavros_launch.py namespace:=drone0 autopilot:=ardupilot fcu_url:=udp://:14550@ tgt_system:=1 mavros_config_file:=/root/ws/project_emulator/config/config.yaml | |
| New container shell (W4–W8), workspace loaded | W4–W8 | ssh chameleon; docker exec -it as2 bash -c "source /root/ws/install/setup.bash && exec bash" | (if you type the source line separately, wait for the root@e-vm prompt first, or ROS reports "Package 'as2_platform_mavlink' not found") |
| Platform (Aerostack2 commands → MAVROS) | W4 | ros2 launch as2_platform_mavlink as2_platform_mavlink_launch.py namespace:=drone0 platform_config_file:=/root/ws/project_emulator/config/config.yaml | |
| State estimator (position in earth frame) | W5 | ros2 launch as2_state_estimator state_estimator_launch.py namespace:=drone0 config_file:=/root/ws/project_emulator/config/config.yaml | |
| Motion controller | W6 | ros2 launch as2_motion_controller controller_launch.py namespace:=drone0 config_file:=/root/ws/project_emulator/config/config.yaml plugin_name:=pid_speed_controller | |
| Motion behaviors (takeoff, land, go_to) | W7 | ros2 launch as2_behaviors_motion motion_behaviors_launch.py namespace:=drone0 config_file:=/root/ws/project_emulator/config/config.yaml | |
| Check the link | W8 | ros2 topic echo /drone0/mavros/state --once; ros2 topic echo /drone0/platform/info --once | connected: true, mode LAND; platform connected, DISARMED |
| Check the position | W8 | ros2 topic echo /drone0/self_localization/pose --once | frame earth, x 10.0 y -0.5 z 0.32 |
| Reset before each mission (on the ground) | W8 | ros2 service call /drone0/mavros/cmd/arming mavros_msgs/srv/CommandBool "{value: false}"; ros2 service call /drone0/mavros/set_mode mavros_msgs/srv/SetMode "{custom_mode: 'LAND'}" | success=True, mode_sent=True |
| Take off to 5 m and land (offboard → arm → takeoff → 5 s → land) | W8 | cd /root/ws/project_emulator; python3 mission_takeoff_land.py -n drone0 | "Takeoff completed at 5.04 m", landed |
| Record the position | W9 | ros2 topic echo /drone0/self_localization/pose --csv > /root/ws/notes/tests/T5.4_square_pose.csv | |
| Fly a 10 m square at 5 m | W8 | python3 mission_square.py -n drone0 | |
| Summarize the path (after Ctrl+C in W9) | W8 | python3 summarize_path.py /root/ws/notes/tests/T5.4_square_pose.csv | corners within 0.13 / 0.11 / 0.09 / 0.04 m, max z 5.06 m |
| Stop | all | Ctrl+C in each window (stop MAVROS before aerpawlib: both use UDP 14550) | |

Fixes needed to run it on our setup (each found by a failed test, logs in ws/notes/tests/T5.*):
- Build link error with the AS2 1.1.3 binary (no tf2::doTransform for TrajectorySetpoints): platform rejects non-odom trajectory references.
- MAVROS topics were /drone0/mavros/mavros/*: MAVROS launched in namespace drone0.
- FCU URL empty after that: fcu_url / tgt_system are launch arguments.
- Takeoff rejected, no earth frame (use_gps: true waits for an origin): use_gps: false, as in Stage 4.
- Square cut two corners (go_to finished early): the mission waits until within 0.5 m of each corner.

Notes:
- The AS2 1.1.3 binary returns FAILED for arm()/offboard() if already armed/GUIDED → reset before each mission.
- Positions printed by the missions lag; use the recorded CSV.
- Shortcuts: ws/project_emulator/launch_as2.bash starts W3–W7 in one tmux session; run_tests.bash runs build/check/reset/takeoff/square with logs.

✅ Stage 5 complete (arm, GUIDED, takeoff, land, position moves).

## Stage 4: Sensors (Oct 20, 2026)

Changes (diffs): package.xml + CMakeLists.txt (nav_msgs, sensor_msgs);
aerpaw_platform.hpp (includes, private members: frame ids, 4 sensors, 4 MAVROS subscriptions);
aerpaw_platform.cpp (tf_utils include; configureSensors relays MAVROS → sensor_measurements).

| Action | Window | Command | Result |
|---|---|---|---|
| MAVROS in drone namespace | W3 | ros2 launch mavros apm.launch fcu_url:=udp://:14550@ namespace:=drone0 | logs as drone0.mavros.* |
| Build + run platform | W4 | cd /root/ws; colcon build --symlink-install; source install/setup.bash; ros2 launch as2_platform_aerpaw as2_platform_aerpaw_launch.py | "relaying MAVROS odom, imu, gps, battery" |
| Compare odom | W6 | ros2 topic echo /drone0/mavros/local_position/odom --once; ros2 topic echo /drone0/sensor_measurements/odom --once | same values; frames map/base_link → drone0/odom, drone0/base_link |
| State estimator | W5 | ros2 launch as2_state_estimator state_estimator_launch.py namespace:=drone0 plugin_name:=raw_odometry | "Earth to map set to 0, 0, 0" |
| Self-localization (ground) | W6 | ros2 topic echo /drone0/self_localization/pose --once | frame earth; x 9.94, y -0.02, z 0.34 |
| Fly by hand | W6 | /drone0/mavros/set_mode GUIDED; /drone0/mavros/cmd/arming true; /drone0/mavros/cmd/takeoff 5.0 | all success |
| Self-localization (air) | W6 | ros2 topic echo /drone0/self_localization/pose --once | z 5.28 |
| Land | W6 | /drone0/mavros/set_mode LAND | landed, auto-disarmed |

Notes:
- MAVROS topics now under /drone0/mavros/...; platform uses relative "mavros/..." names.
- Local z ≈ 0.3 m on the ground (ArduPilot offset); Aerostack2 matches MAVROS exactly.
- Harmless MAVROS warnings: "Unexpected command 11" (SET_MODE ack), "stale remote address 255.x" (QGC).

✅ Stage 4 complete.

## Stage 3: Empty platform package (Oct 19, 2026)

Package: ~/aerostack2_aerpaw/ws/src/as2_platform_aerpaw
Files: package.xml, CMakeLists.txt, include/as2_platform_aerpaw/aerpaw_platform.hpp,
src/aerpaw_platform.cpp, src/aerpaw_platform_node.cpp, config/control_modes.yaml,
config/platform_config_file.yaml, launch/as2_platform_aerpaw_launch.py
Every contract function present; each logs "not implemented yet" and returns false.

| Action | Window | Command | Result |
|---|---|---|---|
| Create folders | W2 | mkdir -p ~/aerostack2_aerpaw/ws/src/as2_platform_aerpaw/{include/as2_platform_aerpaw,src,config,launch} | |
| Build | W4 | cd /root/ws; colcon build --symlink-install | 1 package finished (11.7 s) |
| Load package | W4 | source install/setup.bash | |
| Run | W4 | ros2 launch as2_platform_aerpaw as2_platform_aerpaw_launch.py | "AERPAW platform started"; 4 control modes listed |
| Node exists | W5 | ros2 node list | /drone0/platform |
| Status | W5 | ros2 topic echo /drone0/platform/info --once | connected: true, armed: false, offboard: false, state: 0 (DISARMED) |
| Services | W5 | ros2 service list \| grep drone0 | set_arming_state, set_offboard_mode, set_platform_control_mode, platform_takeoff, platform_land, platform/state_machine_event, platform/list_control_modes |
| Wiring | W5 | ros2 service call /drone0/set_arming_state std_srvs/srv/SetBool "{data: true}" | success=False; W4 shows "ownSetArmingState(true): not implemented yet" |

Notes:
- connected: true is hard-coded by AerialPlatform in 1.1.3; to be fixed in stage 8.
- build/, install/, log/ are created by root (container); delete from inside the container if needed.
- Run "source install/setup.bash" in every new container shell.

✅ Stage 3 complete.

## Stage 2: Fly by hand (MAVROS only) (Oct 18, 2026)

Window: W4 (inside as2 container), MAVROS running in W3, QGC connected.

| Action | Command | Result |
|---|---|---|
| Check state | ros2 topic echo /mavros/state --once | connected: true, armed: false |
| GUIDED | ros2 service call /mavros/set_mode mavros_msgs/srv/SetMode "{custom_mode: 'GUIDED'}" | mode_sent=True |
| Arm | ros2 service call /mavros/cmd/arming mavros_msgs/srv/CommandBool "{value: true}" | success=True, result=0 |
| Take off 5 m | ros2 service call /mavros/cmd/takeoff mavros_msgs/srv/CommandTOL "{altitude: 5.0}" | success=True; rel_alt ≈ 5.00 |
| Watch height | ros2 topic echo /mavros/global_position/rel_alt | 4.99–5.01 |
| Move 10 m east | ros2 topic pub --once /mavros/setpoint_position/local geometry_msgs/msg/PoseStamped "{header: {frame_id: 'map'}, pose: {position: {x: 10.0, y: 0.0, z: 5.0}}}" | x=10.0, y=-0.04, z=5.01 |
| Land | ros2 service call /mavros/set_mode mavros_msgs/srv/SetMode "{custom_mode: 'LAND'}" | landed, auto-disarmed |

Observations:
- Takeoff returns success immediately; must wait for altitude separately.
- Takeoff while airborne fails with result=4 (MAV_RESULT_FAILED); use position setpoints to change height in flight.
- A single position setpoint is enough for ArduPilot to fly to and hold a position.
- LAND mode disarms automatically after touchdown.
- MAVROS frame: x = east, y = north, z = up (meters from start).

✅ Stage 2 complete.

## Stage 1: Aerostack2 + MAVROS environment (Oct 18, 2026)

| Action | Window | Command | Result |
|---|---|---|---|
| Write Dockerfile | W2 | nano ~/aerostack2_aerpaw/docker/Dockerfile (ros:humble-ros-base + ros-humble-aerostack2, ros-humble-mavros, ros-humble-mavros-extras, geographiclib-tools, wget, tmux; geographiclib datasets script) | file saved |
| Build image | W2 | cd ~/aerostack2_aerpaw; docker build -t as2-aerpaw docker | as2-aerpaw:latest built (536 s) |
| Remove old container | W2 | docker ps -a --filter name=as2; docker rm as2 | leftover aerostack2/humble container removed |
| Start container | W3 | docker run -it --rm --name as2 --network container:E-VM-X0841-M1 -v ~/aerostack2_aerpaw/ws:/root/ws as2-aerpaw bash | prompt root@e-vm-x0841-m1:~/ws# |
| Start MAVROS | W3 | ros2 launch mavros apm.launch fcu_url:=udp://:14550@ | connected; param download log flood (harmless) |
| Open 2nd shell | W4 | docker exec -it as2 bash | inside container |
| Check state | W4 | ros2 topic echo /mavros/state --once | connected: true, armed: false, mode: LAND, system_status: 3 |
| Check GPS | W4 | ros2 topic echo /mavros/global_position/global --once | lat 35.7274877, lon -78.6962707, alt -34.17 (ellipsoid height) |
| Check local position | W4 | ros2 topic echo /mavros/local_position/pose --once | x 0.36, y 0.58, z 0.04, frame map |

Observations:
- Connection path: C-VM mavlink-router → E-VM address UDP 14550 → shared network (--network container:E-VM-X0841-M1) → MAVROS.
- fcu_url default in apm.launch is a USB serial port; overridden with udp://:14550@.
- MAVROS target system ID defaults to 1, matching the emulator drone.
- Don't run aerpawlib experiments while MAVROS is running (both use UDP 14550).

✅ Stage 1 complete.

## Stage 0: Test bench (Oct 18, 2026)

Window: W2 (Chameleon) unless noted.

| Action | Command | Result |
|---|---|---|
| Project + reference clones | mkdir -p ~/aerostack2_aerpaw/reference ~/aerostack2_aerpaw/ws/src; cd ~/aerostack2_aerpaw/reference; git clone --branch 1.1.3 https://github.com/aerostack2/aerostack2.git; git clone --branch 1.1.0 https://github.com/aerostack2/as2_platform_mavlink.git | git describe --tags → 1.1.3, 1.1.0 |
| Clone emulator | cd ~/aerostack2_aerpaw; git clone https://github.com/teaching-on-testbeds/aerpaw-emulator.git; cd aerpaw-emulator; git checkout 298ba60 | at commit 298ba60 |
| Docker | docker --version (install via get.docker.com if missing; sudo usermod -aG docker cc; re-login) | docker run hello-world works |
| Build + start emulator | tmux new -s emu; cd ~/aerostack2_aerpaw/aerpaw-emulator; docker compose -f docker-compose.uav.yml up --build -d | C-VM-X0841-M1 healthy; E-VM-X0841-M1, MAVLink-Gateway-X0841 up |
| QGC tunnel (W1, Mac) | ssh -N -L 5760:127.0.0.1:5760 chameleon; QGC TCP link localhost:5760 | drone on ground in Raleigh, disarmed |
| Test flight | cd ~/aerostack2_aerpaw/aerpaw-emulator; docker compose -f docker-compose.uav.yml exec node1-uav-evm run-aerpawlib demo_square | took off, flew 10 m square, landed |

✅ Stage 0 complete.
