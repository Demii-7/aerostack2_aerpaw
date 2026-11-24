# Running Aerostack2 on AERPAW: simple steps

Addresses (from Manifest.txt): E-VM 192.168.122.1, OEO console VM 192.168.122.62. Key: ~/.ssh/id_aerpaw_rsa

## 1. Portal (aerpaw.org)
1. First time only: put your SSH public key (~/.ssh/id_aerpaw_rsa.pub) in your profile BEFORE the
   experiment's first Initiate Development (keys added later are not picked up).
2. Create the experiment (or use as2_aerpaw_demarce2), resource: LPN1 vehicle_uav.
3. Click Initiate Development and wait until it says the session is running.
4. Download the two files from the experiment page: the Layer 2 VPN file (`aerpaw-XM-X1541-common.ovpn`)
   and `Manifest.txt`.

## 2. VPN
1. Double-click the .ovpn file to add it to Tunnelblick (first time only), then click Connect.
2. Every time after connecting, run this once (the VPN drops big packets; without it ssh hangs):
```
sudo ifconfig tap0 mtu 1300
```

## 3. Terminal 1: telemetry tunnel for QGroundControl
```
ssh -i ~/.ssh/id_aerpaw_rsa -N -L 5760:127.0.0.1:5760 root@192.168.122.62
```
Leave it running. In QGroundControl: Application Settings > Comm Links > Add > Type TCP,
host 127.0.0.1, port 5760 > OK > Connect. The drone appears on the map.
Only watch in QGroundControl: do not change modes or upload missions (the filter stops the session).

## 4. Terminal 2: start Aerostack2 on the E-VM
```
ssh -i ~/.ssh/id_aerpaw_rsa root@192.168.122.1
```
then, on the E-VM:
```
cd /root/aerostack2_aerpaw/ws/project_emulator
export RESULTS_DIR=/root/Results/run_$(date +%m%d_%H%M) && mkdir -p $RESULTS_DIR
screen -dmS as2_guard python3 aerpaw_filter_guard.py --log $RESULTS_DIR/guard.log --geofence /root/AERPAW-Dev/AHN/C-VM/MAVLink_Filter/Geofences/copter_geofence.kml
./launch_as2.bash -a -S -w /root/aerostack2_aerpaw/ws -u udp://:14570@127.0.0.1:14550 -s 1
```
Wait about 45 seconds, then start the mission:
```
source /opt/ros/humble/setup.bash && source /root/aerostack2_aerpaw/ws/install/setup.bash
python3 mission_aerpaw.py -n drone0
```
It prints "waiting for the safety pilot to arm...".

## 5. Terminal 3: arm (OEO console)
```
ssh -i ~/.ssh/id_aerpaw_rsa root@192.168.122.62
source /root/.ap-set-experiment-env.sh
/root/workarea/AERPAW-Dev/OEO/OEO-CONSOLE/InstallScripts/startOEOConsole.sh
```
In the console type:
```
agent 1 arm
```
Only use `arm` here. set_mode / takeoff / land / rtl make the filter stop the session.

## 6. Watch
In QGroundControl: GUIDED, climb to about 24 m, a 20 m square at 25 m, LAND, disarm (about 3 minutes).

## 7. After the flight
- Logs on the E-VM, in $RESULTS_DIR (guard.log, as2_*.log). To copy them to the Mac (from a Mac terminal):
```
scp -r -i ~/.ssh/id_aerpaw_rsa root@192.168.122.1:/root/Results ~/Downloads/aerpaw_results
```
- Stop Aerostack2 on the E-VM: `./launch_as2.bash -k -S; screen -S as2_guard -X quit`
- One flight per session: the drone ends in LAND and cannot be armed again. To fly again:
  portal > Save & Exit, then Initiate Development, then start from step 2.
