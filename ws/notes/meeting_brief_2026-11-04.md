# Meeting brief: Nov 4, 2026

## Oct 20 ask → status
"Use as2_platform_mavlink with the ArduPilot changes instead of an AERPAW platform": done on the emulator.

- Compared both (ws/notes/platform_comparison.md): every job left in our plan (stages 5–8: arm, GUIDED,
  takeoff, land, position/speed commands, emergency stop/hover, lost link) already exists in the ArduPilot
  version of as2_platform_mavlink, through the same MAVROS services we tested by hand in stage 2.
  Finishing ours would have rebuilt it. Adopted it (branch stage5-pivot-mavlink-platform).
- Flew it on the AERPAW emulator through Aerostack2 (Nov 2–3, logs in ws/notes/tests/T5.*):

| Test | Result |
|---|---|
| T5.1 build against our Aerostack2 1.1.3 image | ✅ after 1 small fix |
| T5.2 MAVROS ↔ platform ↔ estimator | ✅ connected, DISARMED, position in earth frame |
| T5.3 GUIDED → arm → takeoff → land | ✅ takeoff completed at 5.04 m, landed |
| T5.4 10 m square at 5 m (Aerostack2 version of demo_square) | ✅ all 4 corners within 0.13 m, max z 5.06 m |

- 5 integration issues found and fixed, each by a failing test (table in Documentation.md, Stage 5):
  link error with the 1.1.3 binary, MAVROS namespace, FCU URL, estimator origin, go_to finishing early.
- Our own as2_platform_aerpaw (stages 3–4 + stage 5 WIP) is kept on its branches for reference.

## What's left that is ours (AERPAW-specific)
1. Two UAVs on the emulator (stage 9): launch_as2.bash already takes -n / -u / -s per drone.
2. Real AERPAW: safety-pilot arming, geofence, running on a real E-VM / C-VM (stage 10).
3. Upstream-quality fixes: go_to early success, 2-line as2_core arm/offboard fix.
4. Back to deliverable 2 (coordination behaviors) now that flights work.

## Questions for her
- Run Aerostack2 on each E-VM, or on one ground node talking to all drones? (Oct 13 question)
- OK to depend on a third-party fork (AS2_ardupilot), or upstream the ArduPilot changes to aerostack2?
- What's the path to a real AERPAW C-VM test slot?
