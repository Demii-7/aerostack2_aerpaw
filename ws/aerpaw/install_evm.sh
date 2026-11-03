#!/bin/bash
# Install ROS 2 Humble + Aerostack2 + MAVROS natively on an AERPAW E-VM and build
# this workspace. Run once, as root, in the E-VM during the Development session
# (the E-VM is a container: no Docker inside it, so we install what our as2-aerpaw
# Docker image has). Then "Save" the experiment in the portal so the testbed
# run uses the same image.
#
#   git clone https://github.com/Demii-7/aerostack2_aerpaw.git /root/aerostack2_aerpaw
#   cd /root/aerostack2_aerpaw && git checkout stage5-pivot-mavlink-platform
#   ./ws/aerpaw/install_evm.sh
#
# Needs internet access from the E-VM (true in the emulator; check on AERPAW with
# "curl -I https://packages.ros.org" first, and ask AERPAW support if it fails).
# Needs Ubuntu 22.04 (jammy): ROS 2 Humble binaries exist only for 22.04.

set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"

. /etc/os-release
echo "E-VM OS: ${PRETTY_NAME}"
if [[ "${VERSION_CODENAME}" != "jammy" ]]; then
  echo "ROS 2 Humble needs Ubuntu 22.04 (jammy), found ${VERSION_CODENAME}. Stop." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y curl gnupg lsb-release software-properties-common screen tmux wget
add-apt-repository -y universe

# ROS 2 apt repository (https://docs.ros.org/en/humble/Installation/Ubuntu-Install-Debs.html)
curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
  -o /usr/share/keyrings/ros-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] \
http://packages.ros.org/ros2/ubuntu ${VERSION_CODENAME} main" > /etc/apt/sources.list.d/ros2.list
apt-get update

# Same packages as docker/Dockerfile (as2-aerpaw image)
apt-get install -y \
  ros-humble-ros-base \
  ros-humble-aerostack2 \
  ros-humble-mavros \
  ros-humble-mavros-extras \
  geographiclib-tools \
  python3-colcon-common-extensions

wget -q https://raw.githubusercontent.com/mavlink/mavros/ros2/mavros/scripts/install_geographiclib_datasets.sh \
  -O /tmp/install_geographiclib_datasets.sh
bash /tmp/install_geographiclib_datasets.sh

# Build only our platform (Aerostack2 itself comes from apt)
set +u
source /opt/ros/humble/setup.bash
set -u
cd "${repo}/ws"
colcon build --symlink-install --packages-select as2_platform_mavlink --cmake-args -DBUILD_TESTING=OFF

echo
echo "Installed. Workspace: ${repo}/ws"
echo "Next: cp ${repo}/ws/aerpaw/startVehicle.sh /root/Profiles/ProfileScripts/Vehicle/startVehicle.sh"
echo "      and uncomment ./Vehicle/startVehicle.sh in /root/startexperiment.sh"
