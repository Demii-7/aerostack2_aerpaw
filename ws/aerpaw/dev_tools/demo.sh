#!/bin/bash
# demo.sh: one-command Aerostack2 flight on AERPAW Development, run from the Mac.
# Needs: the AERPAW VPN up and a Development session running. Watch it in QGroundControl.
# Sequence: pilot sets ALT_HOLD (LAND is not armable) -> guard + Aerostack2 start on the E-VM
# -> mission starts (waits for arm) -> pilot arms via OEO -> GUIDED, takeoff 24 m,
# 20 m square west/north at 25 m, LAND -> live status every 5 s until disarmed.
here="$(cd "$(dirname "$0")" && pwd)"; cd "$here"
EVM=192.168.122.1
step() { echo; echo "=== $(date -u +%H:%M:%S) UTC  $*"; }

step "0/5 VPN"
if ! ifconfig | grep -q "inet 192.168.122."; then
  osascript -e 'tell application "Tunnelblick" to connect "aerpaw-XM-X1541-common"' >/dev/null
  for i in $(seq 1 12); do ifconfig | grep -q "inet 192.168.122." && break; sleep 5; done
fi
ifconfig | grep "inet 192.168.122." || { echo "VPN not up"; exit 1; }

step "1/5 pilot view: drone must be disarmed and NOT in LAND (fresh session = ALT_HOLD)"
# Never change the mode from the OEO console: the filter treats it as a violation and exits.
st=$(./oeo.sh none 6 | grep " armed " | tail -1); echo "$st"
echo "$st" | grep -q "mode ALT_HOLD\|mode STABILIZE\|mode GUIDED" || {
  echo "Drone is not in an armable mode (it is left in LAND after a flight)."
  echo "Restart the session: portal -> Save & Exit, then Initiate Development (~5 min), then rerun."; exit 1; }

step "2/5 E-VM: start filter guard + Aerostack2 (AERPAW mode), ~60 s"
./rrun.sh $EVM evm_start.sh evm_start_out.txt
grep -E "^connected|^mode:|vehicle link" evm_start_out.txt | head -4

step "3/5 E-VM: start mission (it waits for the pilot to arm), ~25 s"
./rrun.sh $EVM evm_mission.sh evm_mission_out.txt
tail -2 evm_mission_out.txt

step "4/5 pilot: arm via OEO console"
./oeo.sh arm 15 | grep -E "FEEDBACK|armed" | tail -3

step "5/5 flight (status about every 15 s; ends when landed and disarmed, max ~6 min)"
seen_air=0
for i in $(seq 1 25); do
  line=$(./oeo.sh none 6 | grep " armed " | tail -1); echo "$line"
  echo "$line" | grep -q "armed 1" && seen_air=1
  [ $seen_air = 1 ] && echo "$line" | grep -q "armed 0" && break
done

step "done: guard summary (nothing should be blocked)"
./rrun.sh $EVM evm_status.sh evm_status_out.txt >/dev/null
grep summary evm_status_out.txt | tail -1 | python3 -c "
import sys, json
l = sys.stdin.read(); d = json.loads(l[l.index('{'):])
print('blocked:', d['blocked'] or 'none')
f = d['forwarded']; print('forwarded commands:', sum(v for k, v in f.items() if k.startswith('COMMAND')))"
