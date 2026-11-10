#!/usr/bin/env python3
"""AERPAW-safe mission: needs the stack started with launch_as2.bash -a (aerpaw.enabled).

Follows the AERPAW MAVLink filter rules (AERPAW User Manual 5.1.3):
safety pilot arms -> GUIDED -> takeoff (20-110 m) -> global waypoints -> back over
the takeoff point -> LAND. Emulator: the pilot is simulated with the E-VM's
auto_arm.py (see run_tests.bash aerpaw).
"""

import argparse
from time import sleep

from as2_python_api.drone_interface import DroneInterface
from mission_square import fly_to, step
import rclpy


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('-n', '--namespace', default='drone0')
    parser.add_argument('--side', type=float, default=20.0, help='square side (m)')
    parser.add_argument('--speed', type=float, default=3.0)
    parser.add_argument('--alt', type=float, default=25.0,
                        help='flying height (m above start, 20-110 on AERPAW)')
    args = parser.parse_args()

    rclpy.init()
    drone = DroneInterface(drone_id=args.namespace, use_sim_time=False, verbose=False)

    # The safety pilot arms. The platform's arm() waits for it; with the AS2 1.1.3
    # binary arm() returns False if the pilot already armed, so check first.
    if drone.info['armed']:
        ok = step('arm (already armed by pilot)', True)
    else:
        print('waiting for the safety pilot to arm...', flush=True)
        ok = step('arm (by pilot)', drone.arm())
    ok = ok and step('offboard (GUIDED)', drone.offboard())
    # Height comes from config_aerpaw.yaml takeoff.height (25 m); the goal value is not used.
    ok = ok and step('takeoff', drone.takeoff(height=25.0, speed=1.0))

    if ok:
        # DroneInterface.position lags right after takeoff (T6 run 2 read 22.5 m while the
        # platform reported 25), so fly at the commanded height, not the measured one.
        x0, y0, _ = drone.position
        z = args.alt
        print(f'home (earth frame): x {x0:.2f} y {y0:.2f}, flying at z {z:.1f}', flush=True)
        s = args.side
        path = [[x0 + s, y0, z], [x0 + s, y0 + s, z], [x0, y0 + s, z], [x0, y0, z]]
        for goal in path:
            ok = step(f'go_to {[round(v, 1) for v in goal]}', fly_to(drone, goal, args.speed, tol=1.0))
            print(f'  position: {[round(v, 2) for v in drone.position]}', flush=True)
            if not ok:
                break
            sleep(1.0)

    # Land only over the takeoff point (filter: within 5 m); the platform refuses otherwise.
    step('land', drone.land(speed=0.5))
    print(f'final position: {[round(v, 2) for v in drone.position]}', flush=True)

    drone.shutdown()
    rclpy.shutdown()


if __name__ == '__main__':
    main()
