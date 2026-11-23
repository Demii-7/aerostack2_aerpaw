#!/usr/bin/env python3
"""Guard proxy for the AERPAW MAVLink filter.

AERPAW's MAVLink filter (C-VM, MAVLink_Filter/filter_safety_checker.py with
allowed-copter.jsonc) shuts the vehicle link down for the rest of the session
on the first message it does not allow, and puts the drone in LOITER. Only a
restart of the Development session brings it back.

This proxy runs on the E-VM between MAVROS and the filter and applies the same
rules to everything we send. A message the filter would reject is dropped and
logged instead of forwarded, so a bug on our side shows up in the log and the
link stays up. Vehicle -> MAVROS traffic is forwarded unchanged.

    C-VM filter --UDP--> E-VM :LISTEN (this proxy) <--UDP--> MAVROS on :MAVROS_PORT

Usage on the E-VM:
    python3 aerpaw_filter_guard.py --listen 14550 --mavros-port 14570 --log guard.log &
    ./launch_as2.bash -a -S -u udp://:14570@127.0.0.1:14550
--audit forwards everything (only logs what the filter would reject).
No dependencies beyond Python 3.
"""

import argparse
import json
import math
import signal
import socket
import struct
import sys
import time
from collections import Counter

# allowed-copter.jsonc "allowed" (message ids)
ALLOWED_MSGS = {
    0: 'HEARTBEAT', 20: 'PARAM_REQUEST_READ', 21: 'PARAM_REQUEST_LIST', 39: 'MISSION_ITEM',
    40: 'MISSION_REQUEST', 43: 'MISSION_REQUEST_LIST', 44: 'MISSION_COUNT',
    45: 'MISSION_CLEAR_ALL', 47: 'MISSION_ACK', 51: 'MISSION_REQUEST_INT',
    66: 'REQUEST_DATA_STREAM', 76: 'COMMAND_LONG', 84: 'SET_POSITION_TARGET_LOCAL_NED',
    86: 'SET_POSITION_TARGET_GLOBAL_INT',
}
# The filter validates COMMAND_INT like COMMAND_LONG (validate_command).
COMMAND_INT = 75
COMMAND_LONG = 76
NAMES = {**ALLOWED_MSGS, **{
    2: 'SYSTEM_TIME', 4: 'PING', 11: 'SET_MODE', 23: 'PARAM_SET', 41: 'MISSION_SET_CURRENT',
    69: 'MANUAL_CONTROL', 70: 'RC_CHANNELS_OVERRIDE', 73: 'MISSION_ITEM_INT',
    75: 'COMMAND_INT', 82: 'SET_ATTITUDE_TARGET', 110: 'FILE_TRANSFER_PROTOCOL',
    111: 'TIMESYNC', 300: 'PROTOCOL_VERSION'}}
# allowed-copter.jsonc "command"
ALLOWED_CMDS = {21: 'NAV_LAND', 22: 'NAV_TAKEOFF', 115: 'CONDITION_YAW', 176: 'DO_SET_MODE',
                178: 'DO_CHANGE_SPEED', 192: 'DO_REPOSITION', 511: 'SET_MESSAGE_INTERVAL',
                512: 'REQUEST_MESSAGE', 520: 'REQUEST_AUTOPILOT_CAPABILITIES'}
ALLOWED_MODES = {4: 'GUIDED', 9: 'LAND'}
POSITION_TYPEMASK_CHECK = 0b000111000111  # velocity only
MAV_TYPE_GCS = 6


def frames(buf):
    """Yield (start, end, msgid, payload) for each MAVLink v1/v2 frame in a datagram."""
    i = 0
    while i < len(buf):
        if buf[i] == 0xFD and i + 10 <= len(buf):
            length, incompat = buf[i + 1], buf[i + 2]
            msgid = buf[i + 7] | (buf[i + 8] << 8) | (buf[i + 9] << 16)
            end = i + 12 + length + (13 if incompat & 1 else 0)
            yield i, end, msgid, buf[i + 10:i + 10 + length] + bytes(64)  # v2 trims zeros
            i = end
        elif buf[i] == 0xFE and i + 6 <= len(buf):
            length = buf[i + 1]
            end = i + 8 + length
            yield i, end, buf[i + 5], buf[i + 6:i + 6 + length] + bytes(64)
            i = end
        else:
            i += 1


class Guard:

    def __init__(self):
        self.armed = False
        self.arm_time = None
        self.vehicle_mode = None

    def vehicle_msg(self, msgid, p):
        if msgid == 0:
            custom_mode, mav_type, _, base_mode = struct.unpack_from('<IBBB', p, 0)
            if mav_type == MAV_TYPE_GCS:
                return
            armed = bool(base_mode & 0x80)
            if armed and not self.armed:
                self.arm_time = time.time()
            self.armed = armed
            self.vehicle_mode = custom_mode

    def check(self, msgid, p):
        """Return (label, reason) where reason is None if the filter would allow it."""
        name = NAMES.get(msgid, f'MSG_{msgid}')
        if msgid in (COMMAND_LONG, COMMAND_INT):
            cmd = struct.unpack_from('<H', p, 28)[0]
            label = f'{name}:{ALLOWED_CMDS.get(cmd, cmd)}'
            if cmd not in ALLOWED_CMDS:
                return label, f'command {cmd} not allowed'
            if cmd == 176:
                mode = struct.unpack_from('<f', p, 4)[0]  # param2
                label += f'({ALLOWED_MODES.get(int(mode), mode)})'
                if mode not in ALLOWED_MODES:
                    return label, f'mode {mode} not allowed'
            if cmd == 22 and not self.armed:
                return label, 'takeoff before the vehicle is armed'
            if cmd == 511:
                interval = struct.unpack_from('<f', p, 4)[0]
                if 0 < interval < 20000:
                    return label, f'message interval {interval} us faster than 50 Hz'
            if cmd == 192 and msgid == COMMAND_INT:
                x, y, z = struct.unpack_from('<iif', p, 16)
                label += f'({x / 1e7:.7f},{y / 1e7:.7f},{z:.1f})'
                if not (math.isfinite(z) and x and y):
                    return label, 'reposition without a valid position'
            return label, None
        if msgid in (84, 86):
            mask = struct.unpack_from('<H', p, 48)[0]
            label = f'{name}(mask={mask:#06x})'
            if mask & POSITION_TYPEMASK_CHECK != POSITION_TYPEMASK_CHECK:
                return label, 'position/acceleration target (filter allows velocity only)'
            return label, None
        if msgid == 39:
            cmd = struct.unpack_from('<H', p, 30)[0]
            label = f'{name}:{cmd}'
            return label, (None if cmd == 16 else f'mission item {cmd} not allowed')
        if msgid in ALLOWED_MSGS:
            return name, None
        return name, 'message type not allowed'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--listen', type=int, default=14550, help='port the filter sends to')
    ap.add_argument('--mavros-port', type=int, default=14570, help='port MAVROS binds')
    ap.add_argument('--log', default='aerpaw_filter_guard.log')
    ap.add_argument('--audit', action='store_true', help='forward everything, only log')
    args = ap.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(('0.0.0.0', args.listen))
    sock.settimeout(1.0)
    mavros = ('127.0.0.1', args.mavros_port)
    vehicle = None
    guard = Guard()
    sent, blocked = Counter(), Counter()
    rx = 0
    log = open(args.log, 'a', buffering=1)

    def note(text):
        line = f'{time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())} {text}'
        log.write(line + '\n')
        print(line, flush=True)

    def summary():
        note('summary ' + json.dumps({'from_vehicle_datagrams': rx, 'forwarded': dict(sent),
                                      'blocked': dict(blocked), 'armed': guard.armed,
                                      'vehicle_mode': guard.vehicle_mode}, sort_keys=True))

    def stop(*_):
        summary()
        sys.exit(0)

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)
    note(f'guard: filter -> :{args.listen} <-> MAVROS {mavros} '
         f'({"audit" if args.audit else "enforce"})')
    last = time.time()
    while True:
        try:
            data, addr = sock.recvfrom(65535)
        except socket.timeout:
            data = None
        if data is not None:
            if addr == mavros:
                out = bytearray()
                for start, end, msgid, payload in frames(data):
                    label, reason = guard.check(msgid, payload)
                    if reason is None or args.audit:
                        out += data[start:end]
                    if reason is None:
                        if sent[label] == 0 or msgid in (75, 76):
                            note(f'-> {label}')
                        sent[label] += 1
                    else:
                        blocked[label] += 1
                        note(f'BLOCKED {label}: {reason}' + (' (audit: forwarded)' if args.audit else ''))
                if out and vehicle:
                    sock.sendto(bytes(out), vehicle)
            else:
                if vehicle != addr:
                    note(f'vehicle link from {addr}')
                vehicle = addr
                rx += 1
                for _, _, msgid, payload in frames(data):
                    was = (guard.armed, guard.vehicle_mode)
                    guard.vehicle_msg(msgid, payload)
                    if (guard.armed, guard.vehicle_mode) != was:
                        note(f'vehicle armed={guard.armed} custom_mode={guard.vehicle_mode}')
                sock.sendto(data, mavros)
        if time.time() - last > 30:
            summary()
            last = time.time()


if __name__ == '__main__':
    main()
