#!/usr/bin/env python3
"""Summarize a self_localization/pose CSV from `ros2 topic echo --csv`.

Prints the flight extent, max height, and the closest approach to each square corner.
CSV columns: sec, nanosec, frame_id, x, y, z, qx, qy, qz, qw
"""

import math
import sys

from mission_square import HEIGHT, PATH


def main():
    rows = []
    with open(sys.argv[1]) as f:
        for line in f:
            p = line.strip().split(',')
            if len(p) >= 6:
                t = int(p[0]) + int(p[1]) * 1e-9
                rows.append((t, float(p[3]), float(p[4]), float(p[5])))
    if not rows:
        print('no samples')
        return

    t0 = rows[0][0]
    xs, ys, zs = [r[1] for r in rows], [r[2] for r in rows], [r[3] for r in rows]
    print(f'samples: {len(rows)}, duration: {rows[-1][0] - t0:.1f} s')
    print(f'x: {min(xs):.2f} .. {max(xs):.2f} m   y: {min(ys):.2f} .. {max(ys):.2f} m')
    print(f'max z: {max(zs):.2f} m (target {HEIGHT} m), final z: {zs[-1]:.2f} m')
    for goal in PATH:
        d, r = min((math.dist(goal, r[1:]), r) for r in rows)
        print(f'corner {goal}: closest {d:.2f} m at t={r[0] - t0:.1f} s')


if __name__ == '__main__':
    main()
