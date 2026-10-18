FROM ros:humble-ros-base

RUN apt-get update && apt-get install -y \
        ros-humble-aerostack2 \
        ros-humble-mavros \
        ros-humble-mavros-extras \
        geographiclib-tools \
        wget \
        tmux \
    && rm -rf /var/lib/apt/lists/*

RUN wget -q https://raw.githubusercontent.com/mavlink/mavros/ros2/mavros/scripts/install_geographiclib_datasets.sh \
    && bash install_geographiclib_datasets.sh \
    && rm install_geographiclib_datasets.sh

RUN echo "source /opt/ros/humble/setup.bash" >> /root/.bashrc

WORKDIR /root/ws
