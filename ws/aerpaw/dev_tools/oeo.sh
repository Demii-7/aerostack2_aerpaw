#!/bin/bash
# oeo.sh VERB WAIT [PARAMS...]: run an OEO console command on agent 1 from the Mac.
here="$(cd "$(dirname "$0")" && pwd)"
verb=$1; wait=$2; shift 2
tmp=$(mktemp)
{ echo "VERB='$verb'; WAIT='$wait'; PARAMS='$*'"; cat "$here/oeo_cmd.sh"; } > "$tmp"
"$here/rrun.sh" 192.168.122.62 "$tmp" "$here/oeo_last.txt"
rm -f "$tmp"; cat "$here/oeo_last.txt"
