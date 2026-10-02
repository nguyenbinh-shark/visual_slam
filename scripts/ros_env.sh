# Shared ROS 2 environment for the Pi5 and the laptop. Sourced by ~/.bashrc and by the scripts.
# Both machines must use the same ROS_DOMAIN_ID to see each other's topics.

source /opt/ros/jazzy/setup.bash

export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-42}"
export RCUTILS_COLORIZED_OUTPUT=1

# If the laptop and the Pi5 cannot discover each other (multicast blocked by the router/firewall),
# list the other machine's IP here (Jazzy unicast discovery), e.g. on the laptop:
# export ROS_STATIC_PEERS="192.168.1.50"
