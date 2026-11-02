# Meeting brief: Nov 4, 2026

## Since Oct 20
- Answered "can we just use as2_platform_mavlink?": yes. See ws/notes/platform_comparison.md.
  Every job left in our plan (stages 5–8: arm, GUIDED, takeoff, land, position/speed commands,
  emergency stop/hover, lost link) already exists in the ArduPilot version of as2_platform_mavlink,
  through the same MAVROS services we tested by hand in stage 2.
- Adopted it: branch stage5-pivot-mavlink-platform
  - platform copied in (ws/src/as2_platform_mavlink, from GQP3715/AS2_ardupilot dea4310)
  - emulator config: MAVROS to the E-VM on UDP 14550, 5 m takeoff (ws/project_emulator/config)
  - one-command launch of the whole stack in tmux (ws/project_emulator/launch_as2.bash)
  - two test missions: takeoff/land, and a 10 m square matching aerpawlib demo_square
- Our own as2_platform_aerpaw is kept for reference; stages 0–4 work (emulator, MAVROS link,
  Docker image) carries over unchanged.

## Test status
- [ ] T5.1 build  - [ ] T5.2 stack up, connected  - [ ] T5.3 takeoff/land  - [ ] T5.4 square
(fill in from ws/notes/tests/T5.x_*.txt)

## What's left that is ours (AERPAW-specific)
1. Two UAVs on the emulator (stage 9): MAVROS port + system ID per drone.
2. Real AERPAW: safety-pilot arming, geofence, running on a real E-VM / C-VM (stage 10).
3. Back to deliverable 2 (coordination behaviors) once flights are reliable.

## Questions for her
- Run Aerostack2 on each E-VM, or on one ground node talking to all drones? (Oct 13 question)
- OK to depend on a third-party fork (AS2_ardupilot), or upstream the ArduPilot changes to aerostack2?
- What's the path to a real AERPAW C-VM test slot?
