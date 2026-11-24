# Demo: Aerostack2 flying on real AERPAW (Development), watched in QGroundControl

All commands run on the Mac, in this folder (`aerpaw_diag`).
One flight per Development session: after a flight the drone sits in LAND, which cannot be armed,
and changing the mode from the OEO console makes AERPAW's filter exit. So start each demo from a fresh session.

## 1. Fresh session (~5-7 min, do it shortly before the meeting)
1. VPN up (Tunnelblick, config `aerpaw-XM-X1541-common`), or:
   `osascript -e 'tell application "Tunnelblick" to connect "aerpaw-XM-X1541-common"'`
2. AERPAW portal -> experiment as2_aerpaw_demarce2 (1600) -> Save & Exit (if a session is running),
   wait until it is idle, then Initiate Development. Wait until it shows the session running.
3. Open QGroundControl; it connects by itself over the VPN. The drone should be on the map, disarmed, ALT_HOLD.

## 2. Fly it
Option A, one command: `./demo.sh`
(checks the mode, starts everything, arms, prints status every ~15 s until landed, then "blocked: none").

Option B, step by step (better for explaining each part):
1. `./rrun.sh 192.168.122.1 evm_start.sh evm_start_out.txt`  (~60 s)
   `grep -E "^connected|^mode:" evm_start_out.txt` -> `connected: true`, `mode: ALT_HOLD`
   Starts our filter guard + Aerostack2 (ROS 2) in AERPAW mode on the E-VM.
2. `./rrun.sh 192.168.122.1 evm_mission.sh evm_mission_out.txt; tail -2 evm_mission_out.txt`  (~25 s)
   -> "waiting for the safety pilot to arm..."
3. `./oeo.sh arm 40`  (the emulated safety pilot arms, same as typing `arm` in the OEO console)
4. Watch QGroundControl: GUIDED -> climb to ~24 m -> 20 m square west/north at 25 m -> LAND -> disarm (~2-3 min).
5. `./rrun.sh 192.168.122.1 evm_status.sh evm_status_out.txt; grep summary evm_status_out.txt | tail -1`
   `"blocked": {}` = every command Aerostack2 sent passed AERPAW's filter.

## What to say while it flies
- Aerostack2 runs on the AERPAW E-VM; its MAVLink platform reaches the drone through AERPAW's real MAVLink filter
  and safety checker, the same path a testbed flight uses.
- Only filter-allowed commands are used: DO_SET_MODE (GUIDED/LAND), NAV_TAKEOFF, DO_REPOSITION waypoints.
- Our guard on the E-VM drops anything the filter would reject, so a bug cannot end the session.

## Do not
- Do not use set_mode / takeoff / land / rtl in the OEO console during the session: the filter sees an
  unexpected mode change and exits (seen Nov 24). Only `arm` is safe.
- Do not send anything from QGroundControl (no mode changes, no missions). Just watch.

## If something goes wrong
- `ssh ... Operation timed out`: VPN dropped. Reconnect and rerun the step.
- Drone stuck in LOITER / no new data in QGroundControl: the filter exited. Fresh session (section 1), then fly again.
