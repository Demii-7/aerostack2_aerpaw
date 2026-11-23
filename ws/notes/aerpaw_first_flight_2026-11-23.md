# First Aerostack2 flight on real AERPAW (Development, Nov 23, 2026)

Experiment as2_aerpaw_demarce2 (ID 1600), LPN1 vehicle_uav, Development (Virtual: ArduCopter SITL on the
C-VM behind AERPAW's real MAVLink filter and safety checker).

## Result
Run 2 flew the full mission through the real filter, with no message rejected and the link still up after landing:
pilot arm (OEO console) -> GUIDED (DO_SET_MODE) -> NAV_TAKEOFF to 24 m -> 20 m square at 25 m with
DO_REPOSITION waypoints (west, north-west, north, home) -> LAND 0.6 m from the takeoff point -> disarmed.
Logs: runs_2026-11-23/run2_success_status.txt (guard, platform and mission logs).

## What was changed (as2_platform_mavlink a89d610, this repo 0e4774a, 8a829d2)
1. MAVROS plugin allowlist in AERPAW mode (sys_status, command, global_position, local_position, imu):
   no TIMESYNC/SYSTEM_TIME, no GET_HOME_POSITION, no param/mission pulls. What reached the filter:
   HEARTBEAT, REQUEST_MESSAGE, REQUEST_DATA_STREAM, DO_SET_MODE, NAV_TAKEOFF, DO_REPOSITION (COMMAND_INT).
2. Mode changes as COMMAND_LONG DO_SET_MODE (GUIDED 4 / LAND 9) instead of SET_MODE.
3. Waypoints as COMMAND_INT DO_REPOSITION instead of position SET_POSITION_TARGET_GLOBAL_INT.
4. launch_as2.bash -a requests telemetry once with REQUEST_DATA_STREAM (allowed).
5. ws/project_emulator/aerpaw_filter_guard.py on the E-VM between MAVROS and the filter: applies the
   filter's rules (message types, commands, modes, typemask, takeoff only when armed, waypoint altitude 20-120 m,
   inside the geofence KML) and drops anything the filter would reject, so a bug cannot end the session.

## Runs
- Run 1 (20:21 UTC): link, arm, GUIDED and takeoff passed the filter. The first waypoint, 20 m EAST of the start,
  was outside copter_geofence.kml (the start point is < 20 m from the fence's east edge); the safety checker
  rejected it, the filter switched the drone to LOITER and exited. Not a bug in our code.
- Fix: mission_aerpaw.py flies the square west/north by default (--east/--north), the guard checks the geofence.
- Run 2 (20:48 UTC): full mission, see Result.

## How to run it (from the Mac, VPN up; tools in ws/aerpaw/dev_tools)
1. Portal: Initiate Development (a new session also restarts the C-VM filter; after the filter exits only a
   new session brings it back: Save & Exit, then Initiate Development).
2. `rrun.sh 192.168.122.1 evm_start.sh out.txt`: guard + Aerostack2 in AERPAW mode on the E-VM.
3. `rrun.sh 192.168.122.1 evm_mission.sh out.txt`: mission (waits for the pilot to arm).
4. `oeo.sh arm 40`: the emulated safety pilot arms through the OEO console (C-VM agent, dronekit),
   same as typing `arm` in the OEO console.
5. `rrun.sh 192.168.122.1 evm_status.sh out.txt`: MAVROS state, guard, platform and mission logs.

## Practical notes
- The VPN drops full-size packets: ssh hangs at key exchange or on large outputs. rrun.sh uses
  `-o KexAlgorithms=curve25519-sha256` and sends output gzipped in small paced chunks.
- OEO console commands (agent id "1"): arm, disarm, set_mode, rtl, takeoff, land, ... The console's
  `restart_cvm` went to the E-VM's agent, not the C-VM, and did not restart the filter.
- The C-VM is not reachable from the E-VM; filter messages go to the OEO console as agent feedback.
