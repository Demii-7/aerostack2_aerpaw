#!/usr/bin/env python3
"""Stage 7 test: Aerostack2 version of aerpawlib demo_square (10 m square at 5 m)."""

import argparse
import math
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


def fly_to(drone, goal, speed, tol=0.5, timeout=60.0):
    """go_to, then wait until the drone is really within tol of goal.

    Observed on the emulator (T5.4 run 2): a go_to sent right after a finished
    go_to or takeoff reports success at once, so the next corner was sent early
    and the square was cut. The wait makes the mission independent of that.
    """
    if not drone.go_to.go_to_point(goal, speed=speed):
        return False
    t = 0.0
    while math.dist(drone.position, goal) > tol and t < timeout:
        sleep(0.2)
        t += 0.2
    return math.dist(drone.position, goal) <= tol


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
        ok = step(f'go_to {goal}', fly_to(drone, goal, SPEED))
        print(f'  position: {drone.position}', flush=True)
        sleep(1.0)
    step('land', drone.land(speed=0.5))

    drone.shutdown()
    rclpy.shutdown()


if __name__ == '__main__':
    main()
