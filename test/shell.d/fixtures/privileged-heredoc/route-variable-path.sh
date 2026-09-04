DROP_IN=/etc/systemd/system/omarchy-agent.service.d/override.conf

cat <<EOF | sudo tee "$DROP_IN" >/dev/null
[Service]
ExecStart=$OMARCHY_PATH/bin/omarchy-agent
EOF
