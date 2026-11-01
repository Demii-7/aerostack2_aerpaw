#!/usr/bin/env python3
"""Stage 7 test: Aerostack2 version of aerpawlib demo_square (10 m square at 5 m)."""

import argparse
from time import sleep

from as2_python_api.drone_interface import DroneInterface
import rclpy

HEIGHT = 5.0
SIDE = 10.0
SPEED = 2.0
# earth frame, ENU, origin = position at start (x east, y north)
PATH = [
    [SIDE, 0.0, HEIGHT],
    [SIDE, SIDE, HEIGHT],
    [0.0, SIDE, HEIGHT],
    [0.0, 0.0, HEIGHT],
]


def step(name, ok):
    print(f'{name}: {"OK" if ok else "FAILED"}', flush=True)
    return ok


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('-n', '--namespace', default='drone0')
    args = parser.parse_args()

    rclpy.init()
    drone = DroneInterface(drone_id=args.namespace, use_sim_time=False, verbose=False)

    ok = step('offboard (GUIDED)', drone.offboard())
    ok = ok and step('arm', drone.arm())
    ok = ok and step('takeoff', drone.takeoff(height=HEIGHT, speed=1.0))
    for i, goal in enumerate(PATH):
        if not ok:
            break
        ok = step(f'go_to {goal}', drone.go_to.go_to_point(goal, speed=SPEED))
        print(f'  position: {drone.position}', flush=True)
        sleep(1.0)
    step('land', drone.land(speed=0.5))

    drone.shutdown()
    rclpy.shutdown()


if __name__ == '__main__':
    main()
