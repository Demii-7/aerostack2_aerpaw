# Real AERPAW, first Development session: what we learned (Nov 10, 2026)

Experiment as2_aerpaw_demarce2 (ID 1600, canonical 1541), one portable node (LPN1, vehicle_uav), Development (Virtual).

## E-VM
- Ubuntu 22.04.5, internet works (apt, GitHub, packages.ros.org over http).
- The E-VM is itself a non-privileged Docker container: `docker run` fails with
  `unshare: operation not permitted` (ws/notes q1). Install natively instead.
- `bash ws/aerpaw/install_evm.sh` installed ROS 2 Humble, Aerostack2 1.1.3, MAVROS 2.16 and built
  as2_platform_mavlink (34 s). Saved in the portal.
- SSH keys: only keys present in the portal profile at an experiment's first Initiate Development work
  for that experiment (new keys were refused on experiment 1599 even after restarts).

## Vehicle link (read from AERPAW's own C-VM scripts, a copy of which is on the OEO VM under
/root/workarea/AERPAW-Dev/AHN/C-VM)
- In Virtual mode the C-VM runs ArduCopter SITL -> mavlink-routerd -> the MAVLink filter
  (`MAVLink_Filter/filter_safety_checker.py`, listening on C-VM UDP 14651) -> E-VM 192.168.32.26:14550.
  AERPAW's own scripts on the E-VM connect with `--conn :14550`; our `fcu_url udp://:14550@` is correct.
- The safety checker runs on the C-VM, TCP 14580.

## The filter (exact rules)
Allowed from the E-VM to the vehicle (allowed-copter.jsonc): HEARTBEAT, PARAM_REQUEST_LIST/READ,
REQUEST_DATA_STREAM, COMMAND_LONG/COMMAND_INT, MISSION_ITEM (+ mission protocol messages),
SET_POSITION_TARGET_GLOBAL_INT, SET_POSITION_TARGET_LOCAL_NED.
- Commands: NAV_LAND 21, NAV_TAKEOFF 22, CONDITION_YAW 115, DO_SET_MODE 176, DO_CHANGE_SPEED 178,
  DO_REPOSITION 192, SET_MESSAGE_INTERVAL 511 (max 50 Hz), REQUEST_MESSAGE 512,
  REQUEST_AUTOPILOT_CAPABILITIES 520. Modes via DO_SET_MODE: GUIDED (4) and LAND (9) only.
- **Any other message type is fatal**: the filter logs "E-VM Vehicle MAVLink Connection BROKEN", puts the
  vehicle in LOITER and exits. The link stays down until the C-VM services are restarted.
- **SET_POSITION_TARGET_* must be velocity-only**: type_mask must have bits 0b000111000111 set (position
  and acceleration ignored). Position targets are fatal.
- Takeoff is rejected (fatal) before the vehicle is armed and is held until 2 s after arming; the first
  forwarded takeoff records the pad; LAND (NAV_LAND or DO_SET_MODE 9) must be within 5 m of it.
- DO_REPOSITION and MISSION_ITEM waypoints are checked against the geofence.
- Two consecutive vehicle heartbeats in a mode other than the last one the E-VM set are fatal.

## What happened on Nov 10
MAVROS (default plugins) started at 09:04, received the vehicle for a moment, then the link went silent.
MAVROS sends SYSTEM_TIME and TIMESYNC by default (and SET_MODE for mode changes): not allowed, so the
filter exited and put the vehicle in LOITER (seen afterwards: OEO hears sysid 1, custom_mode 5,
disarmed; nothing reaches the E-VM; aerpawlib's GPS logger also gets no heartbeat).

## Consequences for our AERPAW mode (to change before the next attempt)
1. MAVROS must send only allowed messages: a plugin allowlist and no timesync / system_time.
2. Mode changes as COMMAND_LONG DO_SET_MODE (176), not SET_MODE.
3. Waypoints as DO_REPOSITION (192, COMMAND_INT) or MISSION_ITEM current=2 (what aerpawlib does), not
   position-only SET_POSITION_TARGET_GLOBAL_INT. This answers the Stage 7 open question: our current
   waypoint message is rejected.
4. Test against AERPAW's real filter on the Chameleon emulator first, then restart the Development
   session (the filter only restarts with the C-VM services) and retry.
