#!/bin/bash
# oeo_cmd.sh (fed to the OEO VM by rrun.sh after VERB/PARAMS/WAIT are prepended):
# send one OEO console command to agent 1 exactly as the console does, then print
# agent feedback and the vehicle/computer state for WAIT seconds.
cd /root/workarea/AERPAW-Dev/OEO/oeo-tooling && python3 - "$VERB" "$WAIT" $PARAMS <<'EOF' 2>&1 | grep -v Deprecation
import sys, time
import paho.mqtt.client as mqtt
from lib import util, consts, oeo_service
verb, wait, params = sys.argv[1], float(sys.argv[2]), sys.argv[3:]
BROKER = "192.168.32.30"
last = {}
def on_msg(_, __, m):
    try:
        data, meta = util.deserialize_message(m.payload)[:2]
    except Exception:
        return
    t = meta.get("message_type")
    if t == "agent_feedback" or "feedback" in str(t):
        print(time.strftime("%H:%M:%S"), "FEEDBACK", data, flush=True)
    elif t in ("vehicle_data", "computer_data"):
        last[t] = data
sub = mqtt.Client(client_id=f"oeo_cmd_sub_{time.time()}", callback_api_version=mqtt.CallbackAPIVersion.VERSION1)
sub.on_message = on_msg
sub.connect(BROKER, 1883); sub.subscribe("oeo/#", 0); sub.loop_start()
pub = mqtt.Client(client_id=f"oeo_service_oeo_cmd_{time.time()}_pub", callback_api_version=mqtt.CallbackAPIVersion.VERSION1)
pub.connect(BROKER, 1883); pub.loop_start()
mp = oeo_service.MicroservicePublisher(f"oeo_console_cmd_{time.time():.0f}", pub, "oeo_console")
time.sleep(1)
if verb != "none":
    vehicle_cmds = ["arm", "disarm", "set_mode", "rtl", "takeoff", "land", "start_location", "set_geofence"]
    if verb in vehicle_cmds:
        mp.publish(f"oeo/helper/{consts.HELPER_NAME_VEHICLE}/control", consts.MESSAGE_TYPE_VEHICLE_CONTROL,
                   {"target_agent": "1", "verb": verb, "params": params})
    else:
        mp.publish(f"oeo/helper/{consts.HELPER_NAME_COMPUTER}/control", consts.MESSAGE_TYPE_COMPUTER_CONTROL,
                   {"target_agent": "1", "verb": verb, "params": params})
    print(time.strftime("%H:%M:%S"), "sent", verb, params, flush=True)
end = time.time() + wait
while time.time() < end:
    time.sleep(5)
    v = last.get("vehicle_data", {}).get("vehicle", {})
    c = last.get("computer_data", {}).get("computer", {})
    print(time.strftime("%H:%M:%S"), "armed", v.get("status"), "mode", v.get("mode"),
          "alt", (v.get("position") or {}).get("altitude"), "screens", c.get("screens_running"), flush=True)
EOF
