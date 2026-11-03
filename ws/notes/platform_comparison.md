# as2_platform_aerpaw (ours) vs as2_platform_mavlink (ArduPilot version)

Question (meeting Oct 20, 2026): would finishing our AERPAW platform produce the same thing as
as2_platform_mavlink with ArduPilot support? If so, adopt it instead of rebuilding it.

Sources compared:
- ours: ws/src/as2_platform_aerpaw (stages 3–4, commit a596041)
- theirs: ws/src/as2_platform_mavlink, copied from GQP3715/AS2_ardupilot dea4310
  (line numbers below refer to src/mavlink_platform.cpp)

## Our plan, job by job

| Plan stage | Platform job | Ours (today) | as2_platform_mavlink (ArduPilot profile) | Same thing? |
|---|---|---|---|---|
| 4 | Sensors | Relays MAVROS odom, imu, gps, battery in C++ | Relays odom (l.273); imu/gps/battery remapped by mavros_launch.py | Yes, same topics, different plumbing |
| 5 | Arm / disarm | Stub | /mavros/cmd/arming; refuses without link or position; GUIDED first (l.463) | Yes, it's what we planned |
| 5 | Computer control = GUIDED | Stub | /mavros/set_mode GUIDED, waits for confirmation; release → LOITER (l.506) | Yes |
| 6 | Take off | Stub | /mavros/cmd/takeoff, waits for height (l.609) | Yes, same as our Stage 2 manual steps |
| 6 | Land | Stub | /mavros/cmd/land, waits for on-ground or disarm (l.681) | Yes (LAND mode in our plan; same effect) |
| 7 | Position / speed commands | Stub | setpoint_raw/local at 50 Hz: position, speed, trajectory, hover (l.778–983) | Yes, and more (trajectory + accel feed-forward) |
| 8 | Emergency stop | Stub | Force-disarm via MAV_CMD_COMPONENT_ARM_DISARM (l.721) | Yes |
| 8 | Emergency hover | Stub | Switch to BRAKE (l.729) | Yes |
| 8 | Lost connection | Not handled; `connected: true` hard-coded | Starts disconnected; marks disconnected after timeout without MAVROS state (l.96, l.286) | Yes, fixes our Stage 3 note |
| 8 | Pilot takeover | Not handled | Mode change away from GUIDED → offboard=false, Aerostack2 stops streaming (l.304) | Partly; good enough to start |
| 9 | One launch, two drones | — | mavros_config has drone0–drone3 blocks; launch per namespace | Mostly; needs AERPAW port/ID mapping |
| 10 | Safety-pilot arming, geofence, real E-VM | — | Not covered | No: still our work |

Nothing in stages 5–8 needs AERPAW-specific code: every action goes through MAVROS to ArduPilot,
exactly as in our stage 1–4 tests.

## Conclusion

Yes. Finishing ours would rebuild as2_platform_mavlink's ArduPilot profile almost line for line.
Adopt it. Our work shifts to what's genuinely AERPAW-specific:
1. Configuration and launch for the AERPAW emulator / E-VM (ws/project_emulator).
2. Validating it on the emulator (stage 5–7 tests), then multi-UAV (stage 9).
3. AERPAW operational rules (stage 10): safety-pilot arming, geofence, running on a real E-VM.

## Caveats

- Flown on our emulator Nov 2–3, 2026: arm, GUIDED, takeoff (5.04 m), land, 10 m square (corners within
  0.13 m). Needed 5 small fixes, listed in Documentation.md (Stage 5). Stage 8 (emergencies) not tested yet.
- AS2_ardupilot patched 2 lines in as2_core (arm/offboard return true when already in that state).
  Our image uses the 1.1.3 binary without that patch → run missions from a landed, disarmed drone.
- Their smooth-trajectory generator (GCOPTER) needs their patched Aerostack2; we use position go_to instead.
