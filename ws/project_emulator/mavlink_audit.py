#!/usr/bin/env python3
"""Record every MAVLink message our stack sends to the autopilot.

Why: on the real AERPAW testbed a MAVLink filter only lets through GUIDED/LAND
mode changes, takeoff, global waypoints, yaw and speed changes (AERPAW User
Manual 5.1.3). This proxy shows exactly what MAVROS + Aerostack2 send, so the
list can be checked against the filter (and sent to AERPAW support) before a
real flight. No dependencies beyond Python 3.

    vehicle (C-VM router) --UDP--> :LISTEN (this proxy) <--UDP--> MAVROS on :MAVROS_PORT

Usage (emulator, in the as2 container):
    python3 mavlink_audit.py --listen 14550 --mavros-port 14570 --out audit.json &
    ./launch_as2.bash -a -u udp://:14570@127.0.0.1:14550
Stop with Ctrl-C / SIGTERM; the summary is written to --out every 5 s and on exit.
"""

import argparse
import json
import signal
import socket
import struct
import sys
import time
from collections import Counter

MSG = {
    0: 'HEARTBEAT', 2: 'SYSTEM_TIME', 4: 'PING', 11: 'SET_MODE', 20: 'PARAM_REQUEST_READ',
    21: 'PARAM_REQUEST_LIST', 23: 'PARAM_SET', 39: 'MISSION_ITEM', 40: 'MISSION_REQUEST',
    41: 'MISSION_SET_CURRENT', 43: 'MISSION_REQUEST_LIST', 44: 'MISSION_COUNT',
    45: 'MISSION_CLEAR_ALL', 47: 'MISSION_ACK', 51: 'MISSION_REQUEST_INT',
    66: 'REQUEST_DATA_STREAM', 69: 'MANUAL_CONTROL', 70: 'RC_CHANNELS_OVERRIDE',
    73: 'MISSION_ITEM_INT', 75: 'COMMAND_INT', 76: 'COMMAND_LONG', 82: 'SET_ATTITUDE_TARGET',
    84: 'SET_POSITION_TARGET_LOCAL_NED', 86: 'SET_POSITION_TARGET_GLOBAL_INT',
    110: 'FILE_TRANSFER_PROTOCOL', 111: 'TIMESYNC', 126: 'SERIAL_CONTROL',
    233: 'GPS_RTCM_DATA', 246: 'ADSB_VEHICLE', 300: 'PROTOCOL_VERSION',
}
CMD = {
    16: 'NAV_WAYPOINT', 21: 'NAV_LAND', 22: 'NAV_TAKEOFF', 115: 'CONDITION_YAW',
    176: 'DO_SET_MODE', 178: 'DO_CHANGE_SPEED', 192: 'DO_REPOSITION',
    400: 'COMPONENT_ARM_DISARM', 410: 'GET_HOME_POSITION', 511: 'SET_MESSAGE_INTERVAL',
    512: 'REQUEST_MESSAGE', 519: 'REQUEST_PROTOCOL_VERSION',
    520: 'REQUEST_AUTOPILOT_CAPABILITIES',
}
COPTER_MODES = {0: 'STABILIZE', 2: 'ALT_HOLD', 3: 'AUTO', 4: 'GUIDED', 5: 'LOITER', 6: 'RTL',
                9: 'LAND', 16: 'POSHOLD', 17: 'BRAKE'}

# What the AERPAW filter documents as allowed for drones (5.1.3). Everything else
# is "ask AERPAW": the manual does not say whether telemetry/housekeeping
# messages are dropped, ignored or treated as violations.
ALLOWED = {
    'SET_MODE:GUIDED', 'SET_MODE:LAND', 'COMMAND_LONG:NAV_TAKEOFF',
    'COMMAND_LONG:CONDITION_YAW', 'COMMAND_LONG:DO_CHANGE_SPEED', 'MISSION_ITEM(current=2)',
    'SET_POSITION_TARGET_GLOBAL_INT',
}
HOUSEKEEPING = {'HEARTBEAT', 'SYSTEM_TIME', 'TIMESYNC', 'PING', 'PARAM_REQUEST_READ',
                'PARAM_REQUEST_LIST', 'REQUEST_DATA_STREAM', 'MISSION_REQUEST_LIST',
                'MISSION_ACK', 'MISSION_REQUEST_INT', 'MISSION_REQUEST'}


def parse(buf):
    """Yield (msgid, payload) for each MAVLink v1/v2 frame in a UDP datagram."""
    i = 0
    while i < len(buf):
        if buf[i] == 0xFD and i + 10 <= len(buf):
            length, incompat = buf[i + 1], buf[i + 2]
            msgid = buf[i + 7] | (buf[i + 8] << 8) | (buf[i + 9] << 16)
            payload = buf[i + 10:i + 10 + length]
            i += 12 + length + (13 if incompat & 1 else 0)
        elif buf[i] == 0xFE and i + 6 <= len(buf):
            length = buf[i + 1]
            msgid = buf[i + 5]
            payload = buf[i + 6:i + 6 + length]
            i += 8 + length
        else:
            i += 1
            continue
        yield msgid, payload


def label(msgid, payload):
    name = MSG.get(msgid, f'MSG_{msgid}')
    p = payload + bytes(64)  # MAVLink2 trims trailing zeros
    if msgid in (75, 76):
        cmd = struct.unpack_from('<H', p, 28)[0]
        return f'{name}:{CMD.get(cmd, cmd)}'
    if msgid == 11:
        mode = struct.unpack_from('<I', p, 0)[0]
        return f'SET_MODE:{COPTER_MODES.get(mode, mode)}'
    if msgid in (39, 73):
        current = p[35]  # params/x/y/z (28), seq, command, target sys/comp, frame, current
        return f'{name}(current={current})'
    return name


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--listen', type=int, default=14550, help='port the vehicle sends to')
    ap.add_argument('--mavros-port', type=int, default=14570, help='port MAVROS binds')
    ap.add_argument('--out', default='mavlink_audit.json')
    args = ap.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(('0.0.0.0', args.listen))
    sock.settimeout(1.0)
    mavros = ('127.0.0.1', args.mavros_port)
    vehicle = None
    sent = Counter()
    t0 = time.time()

    def write():
        allowed = {k: v for k, v in sent.items() if k in ALLOWED or k.startswith('HEARTBEAT')}
        house = {k: v for k, v in sent.items() if k.split('(')[0] in HOUSEKEEPING and k not in allowed}
        other = {k: v for k, v in sent.items() if k not in allowed and k not in house}
        summary = {'duration_s': round(time.time() - t0, 1),
                   'documented_allowed': allowed, 'housekeeping_ask_aerpaw': house,
                   'not_in_filter_list': other}
        with open(args.out, 'w') as f:
            json.dump(summary, f, indent=2, sort_keys=True)
        return summary

    def stop(*_):
        print(json.dumps(write(), indent=2, sort_keys=True))
        sys.exit(0)

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)
    last = time.time()
    print(f'audit proxy: vehicle -> :{args.listen} <-> MAVROS {mavros}', flush=True)
    while True:
        try:
            data, addr = sock.recvfrom(65535)
            if addr == mavros:
                for msgid, payload in parse(data):
                    sent[label(msgid, payload)] += 1
                if vehicle:
                    sock.sendto(data, vehicle)
            else:
                vehicle = addr
                sock.sendto(data, mavros)
        except socket.timeout:
            pass
        if time.time() - last > 5:
            write()
            last = time.time()


if __name__ == '__main__':
    main()
