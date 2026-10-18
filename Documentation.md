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