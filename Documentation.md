## Stage 0: Test bench

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

## Stage 1: Aerostack2 + MAVROS environment

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

## Stage 2: Fly by hand (MAVROS only)

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

## Stage 3: Empty platform package

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

## Stage 4: Sensors

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
## Stage 5 (pivot): reuse as2_platform_mavlink with the ArduPilot profile

Why: meeting Oct 20, 2026 — with the MAVROS adapter approach nothing is AERPAW-specific, so use
as2_platform_mavlink (ArduPilot-fixed version from https://github.com/GQP3715/AS2_ardupilot, commit dea4310)
instead of finishing as2_platform_aerpaw. That fork already implements stages 5–8 of our plan for ArduPilot:
GUIDED as offboard, arm after GUIDED, MAV_CMD_NAV_TAKEOFF, LAND, position/velocity/trajectory setpoints, BRAKE hover.
Both use Aerostack2 1.1.3, same as our as2-aerpaw image.

Files:
- ws/src/as2_platform_mavlink/ — from AS2_ardupilot dea4310 (BSD-3), AERPAW changes marked "AERPAW change" in the code
- ws/project_emulator/config/config.yaml — emulator config (takeoff 5 m, position go_to, estimator without GPS)
- ws/project_emulator/launch_as2.bash — tmux session as2_<ns>: mavros, platform, estimator, controller, behaviors, viewer; -u fcu_url -s tgt_system
- ws/project_emulator/run_tests.bash — build / check / reset / takeoff / square, logs to ws/notes/tests/T5.x_*
- ws/project_emulator/mission_takeoff_land.py, mission_square.py, summarize_path.py — missions and path summary
- ws/src/as2_platform_aerpaw/ — kept for reference; earlier stage 5 WIP saved on branch stage5-aerpaw-platform-wip

Changes needed to run it on our setup (each found by a failed test, logs kept):
| Test that failed | Cause | Change |
|---|---|---|
| T5.1a build | AS2 1.1.3 binary has no tf2::doTransform for TrajectorySetpoints (link error) | mavlink_platform.cpp: reject non-odom trajectory references instead of converting |
| T5.2 run1 | MAVROS topics were /drone0/mavros/mavros/* (node named mavros inside ns drone0/mavros) | mavros_launch.py: namespace drone0 → /drone0/mavros/* |
| T5.2 run2 | FCU URL empty after the namespace change (YAML key no longer matched) | mavros_launch.py: fcu_url / tgt_system launch args; launch_as2.bash passes udp://:14550@, 1 |
| T5.3 run1 | Takeoff goal rejected: "earth" frame missing, estimator "Waiting for origin" with use_gps: true | config.yaml: use_gps false (as in Stage 4) |
| T5.4 run2 | go_to after a finished go_to/takeoff reports success at once → corners (10,0), (0,10) missed by 2.2–2.4 m | mission_square.py: fly_to() waits until within 0.5 m of the corner |

Known differences from the AS2_ardupilot setup:
- Their Aerostack2 copy has a 2-line as2_core fix (arm/offboard return true when already in that state).
  The 1.1.3 binary does not → run_tests.bash reset (disarm + LAND) before each mission.
- No GCOPTER / trajectory generator: go_to uses go_to_plugin_position (ArduPilot does the tracking).
- Harmless "Invalid transition" warnings (e.g. LANDED -> LANDED), also listed in the AS2_ardupilot README.

Run on Chameleon, Nov 2–3, 2026 (UTC), as2 container started detached (docker run -d ... sleep infinity; docker exec).

| Test | Command (in as2 container, ws/project_emulator) | Result |
|---|---|---|
| T5.1 build | ./run_tests.bash build | 1 package finished (52.4 s) after link fix |
| Launch | ./launch_as2.bash | tmux as2_drone0; estimator "Earth to map set to 0, 0, 0" |
| T5.2 link | ./run_tests.bash check | mavros connected: true, mode LAND; platform connected: true (from MAVROS, no longer hard-coded), DISARMED; self_localization frame earth |
| T5.0 reset | ./run_tests.bash reset | arming success=True, mode_sent=True |
| T5.3 takeoff + land | ./run_tests.bash takeoff | GUIDED OK, arm OK, takeoff OK ("Takeoff completed at 5.04 m"), land OK, final z 0.35 m |
| T5.4 square | ./run_tests.bash square | all OK; corners reached within 0.13 / 0.11 / 0.09 / 0.04 m; max z 5.06 m; final z 0.02 m; 50.3 s |
| Stop | ./launch_as2.bash -k | |

Notes:
- Positions printed by the missions come from DroneInterface; use T5.4_square_pose.csv / summary for the real path.
- Don't run aerpawlib experiments while the stack (MAVROS) is running (both use UDP 14550).

✅ Stage 5–7 equivalent complete on the emulator (arm, GUIDED, takeoff, land, position moves) using as2_platform_mavlink.
