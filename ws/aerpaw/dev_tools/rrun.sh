#!/bin/bash
# rrun.sh HOST SCRIPT OUT: run SCRIPT on HOST (AERPAW VM over the VPN) and save output to OUT.
# The VPN drops full-size packets, so the remote side gzips the output and sends it in
# small paced chunks (each chunk leaves as its own small TCP segment).
host=$1; script=$2; out=$3
{ cat "$script"; echo; } | ssh -o KexAlgorithms=curve25519-sha256 -o IPQoS=none -i ~/.ssh/id_aerpaw_rsa \
  -o ConnectTimeout=20 -o BatchMode=yes -o ServerAliveInterval=15 "root@$host" \
  'bash -s 2>&1 | gzip -c | python3 -c "
import sys, time
d = sys.stdin.buffer.read()
for i in range(0, len(d), 300):
    sys.stdout.buffer.write(d[i:i+300]); sys.stdout.buffer.flush(); time.sleep(0.5)
"' | gunzip -c > "$out"
echo "exit=${PIPESTATUS[1]} bytes=$(wc -c < "$out")"
