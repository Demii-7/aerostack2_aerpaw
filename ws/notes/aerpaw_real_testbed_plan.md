# Running our Aerostack2 stack on the real AERPAW testbed

Researched Nov 3, 2026 from the AERPAW User Manual and the "Hello, AERPAW" tutorial;
AERPAW-mode emulator tests in ws/notes/tests/T6.*.

## How AERPAW runs experiments

1. **Hello, AERPAW** (https://teaching-on-testbeds.github.io/hello-aerpaw/, linked from User Manual §2):
   account at https://aerpaw.org (Experiment Web Portal) → profile → SSH public key → request
   Experimenter role → join your advisor's project.
2. **Create a Canonical experiment**, add a portable node (LPN1) with Node Vehicle = `vehicle_uav`,
   then "Initiate Development". You get an email when the Development session is active.
3. **Development mode** (virtual environment): download the `.ovpn` file and `Manifest.txt`; VPN in
   (Mac: Tunnelblick; AERPAW uses a tap interface), then
   - `ssh -i ~/.ssh/id_rsa_aerpaw -L 5760:127.0.0.1:5760 root@192.168.X.62` → OEO console
     (`./startOEOConsole.sh`), QGroundControl TCP 127.0.0.1:5760;
   - `ssh -i ~/.ssh/id_rsa_aerpaw root@192.168.X.1` → the UAV's E-VM.
   The virtual environment emulates vehicle control "with the same programming interface" as the testbed.
4. **The only entry point is `/root/startexperiment.sh`** on each E-VM: you run it in Development mode,
   AERPAW operators run it in Testbed mode. It calls `Radio/startRadio.sh`, `Traffic/startTraffic.sh`,
   `Vehicle/startVehicle.sh` (in `/root/Profiles/ProfileScripts/`). `/root/stopexperiment.sh` closes
   all `screen` sessions. (User Manual §5.4)
5. **Testbed mode is batch**: everything must be scripted; no SSH during the flight. "Save and Exit"
   in the portal (20–30 min), then submit for testbed execution; scheduling takes days to weeks
   (weather, safety pilot). (User Manual §4.5.3, §4.5.4)

## The rule that matters: the MAVLink filter (User Manual §5.1.3)

Between the E-VM and the autopilot. Drones may only:
- go to a waypoint (lat, lon, alt); change yaw; change speed
- take off to **20–110 m AGL**
- change mode to **GUIDED or LAND**

and must stay in the geofence, out of no-go zones, between 20 and 110 m, and **land within 5 m of the
takeoff point**. The **safety pilot arms**. Any violation, or any mode change not made by the script
(pilot override, failsafe), aborts the experiment. Copter limits in the emulator's copy of the AERPAW
profile: min_alt 20, max_alt 120, speed 1–20 m/s.

**Our Chameleon emulator does not include the filter** (only the geofence files), so the stage 5 tests
(5 m height, 50 Hz local setpoints, our own arm command) passed there but would abort on AERPAW.

## What we changed: AERPAW mode (`aerpaw.enabled`, `launch_as2.bash -a`)

| Filter rule | Normal mode | AERPAW mode |
|---|---|---|
| Pilot arms | sends MAV_CMD arm | waits for the pilot (up to 300 s), never sends arm/disarm |
| GUIDED / LAND only | LOITER on release, BRAKE on emergency hover, forced disarm on kill | GUIDED hold instead of BRAKE, LAND instead of forced disarm, release refused |
| Waypoints only | SET_POSITION_TARGET_LOCAL_NED at 50 Hz (position/speed/trajectory) | global waypoint (SET_POSITION_TARGET_GLOBAL_INT) once per new target + resend every 2 s; only HOVER and POSITION modes |
| 20–110 m | any height | takeoff refused below 20 m, waypoints outside 20–110 m not sent |
| Land within 5 m | land anywhere | land refused > 5 m from the takeoff point (LAND mode) |

Code: `ws/src/as2_platform_mavlink/src/aerpaw_mode.cpp` (+ small hooks in `mavlink_platform.cpp`).
Config: `ws/project_emulator/config/config_aerpaw.yaml`, `control_modes_aerpaw.yaml`.
Mission: `ws/project_emulator/mission_aerpaw.py` (pilot arm → GUIDED → takeoff 25 m → 20 m square → back over takeoff point → LAND).

## Emulator results (T6, Nov 3, 2026)

Stack started like on an E-VM (screen sessions, `-a -S`); safety pilot simulated with the emulator's
`auto_arm.py` (arms in STABILIZE on its own MAVLink link). `test_aerpaw_emulator.sh` runs it all.

| Run | Result |
|---|---|
| T6 run 1 | ❌ takeoff refused: "no GPS fix" (GPS remap broken by the namespace fix) → platform also reads `mavros/global_position/global` |
| T6 run 2 | ✅ waited for pilot, GUIDED, takeoff to 24.9 m, 20 m square at 22.5 m, landed 0.05 m from takeoff |

MAVLink audit (`mavlink_audit.py`, every message we send to the autopilot):

| | aerpawlib demo_square (AERPAW's library) | our stack, AERPAW mode |
|---|---|---|
| Waypoints | MISSION_ITEM current=2 ×4 | SET_POSITION_TARGET_GLOBAL_INT ×19 |
| Takeoff | COMMAND_LONG NAV_TAKEOFF | COMMAND_LONG NAV_TAKEOFF |
| Mode | COMMAND_LONG DO_SET_MODE | SET_MODE GUIDED, LAND |
| Arm/disarm | none | none |
| Housekeeping | PARAM_REQUEST_LIST, MISSION_REQUEST_LIST, REQUEST_DATA_STREAM, COMMAND_LONG REQUEST_AUTOPILOT_CAPABILITIES | PARAM_REQUEST_LIST/READ (930), MISSION_REQUEST_LIST, TIMESYNC (1767), SYSTEM_TIME, COMMAND_LONG GET_HOME_POSITION, REQUEST_MESSAGE |

aerpawlib also sends requests outside the filter's list, so housekeeping is probably tolerated.
**The real unknown is the waypoint message type**: aerpawlib uses MISSION_ITEM (current=2); we use
SET_POSITION_TARGET_GLOBAL_INT. The emulator cannot tell us whether the filter accepts it.

## Plan for the real testbed

1. **Accounts and Hello AERPAW** (you; needs approvals from AERPAW staff and your advisor).
   Run the Hello AERPAW tutorial to confirm VPN, OEO console and QGC work.
2. **Development session, UAV E-VM, baseline**: run the sample vehicle script
   (`Samples/startPreplannedTrajectory.sh`) to see a filter-approved flight in the AERPAW environment.
3. **Check the E-VM**: `cat /etc/os-release` (needs Ubuntu 22.04), `curl -I https://packages.ros.org`
   (needs internet for apt). If either fails, ask AERPAW support (see questions).
4. **Install**: `git clone` this repo to `/root/aerostack2_aerpaw`, branch `stage5-pivot-mavlink-platform`,
   `ws/aerpaw/install_evm.sh`.
5. **Audit run in Development mode**: start `mavlink_audit.py` + `launch_as2.bash -a -S -u udp://:14570@127.0.0.1:14550`
   (commented in `ws/aerpaw/startVehicle.sh`), run `mission_aerpaw.py`, have the virtual pilot arm via the OEO
   console / QGC. If the OEO console reports a filter violation, note which message.
6. **Wire into AERPAW**: `cp ws/aerpaw/startVehicle.sh /root/Profiles/ProfileScripts/Vehicle/startVehicle.sh`,
   uncomment `./Vehicle/startVehicle.sh` in `/root/startexperiment.sh`, test `./startexperiment.sh` and
   `./stopexperiment.sh`.
7. **Save and Exit, submit for testbed execution.** Results come back in `$RESULTS_DIR` (`as2_*.log`, `as2_mission.log`).

## If the filter rejects our waypoints

Send them exactly like aerpawlib: MISSION_ITEM with current=2 (guided waypoint), MAV_FRAME_GLOBAL_RELATIVE_ALT.
MAVROS has no topic for that message; options: (a) raw MAVLink through a MAVROS router ROS endpoint
(`mavros_router/add_endpoint`, mavros_msgs/Mavlink), (b) a small pymavlink sidecar the platform calls,
(c) a thin aerpawlib-based platform. (a) keeps everything in the platform; try it first.
Optional hardening: trim MAVROS plugins (sys_time, param, home_position, waypoint) to cut housekeeping.

## Questions for AERPAW support / advisor

1. Does the filter accept SET_POSITION_TARGET_GLOBAL_INT (position-only, rel. alt) as "navigate to a waypoint",
   or only MISSION_ITEM current=2 like aerpawlib? SET_MODE vs COMMAND_LONG DO_SET_MODE?
2. Are housekeeping messages (TIMESYNC, PARAM_REQUEST_READ, COMMAND_LONG GET_HOME_POSITION / REQUEST_MESSAGE)
   dropped, passed, or counted as violations?
3. Do E-VMs have internet in Development mode (apt for ROS 2), and which Ubuntu version are they?
4. Is the filter active in the Development virtual environment (so step 5 is a real check)?
5. Which geofence and takeoff point apply to our experiment (the 20 m square must fit inside)?

## Known issues

- AS2 sensor topics `sensor_measurements/gps|imu|battery` are empty since the MAVROS namespace fix (the remaps
  do not match the MAVROS plugin sub-nodes). Flight does not use them (position comes from odometry);
  AERPAW mode reads GPS from `mavros/global_position/global` directly.
- DroneInterface.position lags right after takeoff; the mission flies at the commanded height.

## Sources

- AERPAW User Manual: https://sites.google.com/ncsu.edu/aerpaw-user-manual (§2 Hello AERPAW, §4.5.3–4.5.4, §5.1.3 MAVLink Filter, §5.4 Running Sample Experiment Software)
- Hello, AERPAW tutorial: https://teaching-on-testbeds.github.io/hello-aerpaw/
- AERPAW emulator (aerpawlib, AERPAW profile, auto_arm.py): https://github.com/teaching-on-testbeds/aerpaw-emulator (298ba60)
