#!/usr/bin/env python3
"""Stage 5+6 test: GUIDED, arm, take off, hover, land through Aerostack2."""

import argparse
from time import sleep

from as2_python_api.drone_interface import DroneInterface
import rclpy

TAKE_OFF_HEIGHT = 5.0  # informational: platform takeoff.height in config.yaml is what is flown
HOVER_TIME = 5.0


def step(name, ok):
    print(f'{name}: {"OK" if ok else "FAILED"}', flush=True)
    return ok


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('-n', '--namespace', default='drone0')
    args = parser.parse_args()

    rclpy.init()
    drone = DroneInterface(drone_id=args.namespace, use_sim_time=False, verbose=False)

    # ArduPilot runs arming checks against the current mode, so GUIDED comes first.
    ok = step('offboard (GUIDED)', drone.offboard())
    ok = ok and step('arm', drone.arm())
    ok = ok and step('takeoff', drone.takeoff(height=TAKE_OFF_HEIGHT, speed=1.0))
    if ok:
        print(f'position after takeoff: {drone.position}', flush=True)
        sleep(HOVER_TIME)
    step('land', drone.land(speed=0.5))
    print(f'position after land: {drone.position}', flush=True)

    drone.shutdown()
    rclpy.shutdown()


if __name__ == '__main__':
    main()
