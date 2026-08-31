cat <<'EOF' | sudo tee /etc/udev/rules.d/99-omarchy.rules >/dev/null
SUBSYSTEM=="power_supply", RUN+="/usr/bin/omarchy-powerprofiles-set $HOME"
EOF

cat <<"XML" | sudo tee /etc/omarchy/agent.xml >/dev/null
<config path="$HOME/.local/share/omarchy" />
XML
