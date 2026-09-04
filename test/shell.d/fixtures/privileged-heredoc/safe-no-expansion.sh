cat <<EOF | sudo tee /etc/udev/rules.d/99-omarchy.rules >/dev/null
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="/usr/bin/omarchy-powerprofiles-set"
EOF
