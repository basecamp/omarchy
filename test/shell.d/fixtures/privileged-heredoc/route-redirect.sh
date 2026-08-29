# A plain redirect into /etc, no sudo: the command re-execs itself as root.
cat >/etc/omarchy/agent.conf <<EOF
helper=$HOME/.local/share/omarchy/bin/omarchy-agent
EOF
