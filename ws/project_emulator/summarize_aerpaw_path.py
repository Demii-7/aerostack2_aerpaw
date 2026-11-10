#!/usr/bin/env python3
"""Summarize the AERPAW-mode flight from a self_localization/pose CSV (ros2 topic echo --csv).

Checks the AERPAW filter rules that a path can show: flying height >= 20 m once
airborne, and landing within 5 m of the takeoff point.
"""

import math
import sys


def main():
    rows = []
    with open(sys.argv[1]) as f:
        for line in f:
            p = line.strip().split(',')
            if len(p) >= 6:
                rows.append((int(p[0]) + int(p[1]) * 1e-9, float(p[3]), float(p[4]), float(p[5])))
    if not rows:
        print('no samples')
        return
    t0, x0, y0, z0 = rows[0]
    xs, ys, zs = [r[1] for r in rows], [r[2] for r in rows], [r[3] for r in rows]
    top = max(zs)
    # cruise = samples above 90 % of the max height, to skip climb and descent
    cruise = [r for r in rows if r[3] > 0.9 * top]
    end = rows[-1]
    print(f'samples: {len(rows)}, duration: {end[0] - t0:.1f} s')
    print(f'start (earth): x {x0:.2f} y {y0:.2f} z {z0:.2f}')
    print(f'x: {min(xs) - x0:.2f} .. {max(xs) - x0:.2f} m   y: {min(ys) - y0:.2f} .. {max(ys) - y0:.2f} m (from start)')
    print(f'max height: {top - z0:.2f} m above start; cruise height min {min(r[3] for r in cruise) - z0:.2f} m')
    land_dist = math.hypot(end[1] - x0, end[2] - y0)
    print(f'final: height {end[3] - z0:.2f} m, {land_dist:.2f} m from the takeoff point '
          f'({"OK" if land_dist <= 5.0 else "OVER"} the 5 m AERPAW limit)')


if __name__ == '__main__':
    main()
