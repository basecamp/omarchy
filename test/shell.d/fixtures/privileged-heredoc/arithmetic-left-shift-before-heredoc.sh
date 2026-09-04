mask=$((1 << bits))

cat >/etc/omarchy/agent.conf <<EOF
helper=$HOME/.local/share/omarchy/bin/omarchy-agent
EOF
