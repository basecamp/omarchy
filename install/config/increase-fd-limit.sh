# Raise soft file descriptor limit from systemd's default of 1024 to 65536
# so dev tools (VS Code, Docker, dev servers, databases) get the headroom they need
sudo mkdir -p /etc/systemd/system.conf.d /etc/systemd/user.conf.d

sudo tee /etc/systemd/system.conf.d/99-omarchy-nofile.conf >/dev/null <<'EOF'
[Manager]
DefaultLimitNOFILESoft=65536
EOF

sudo cp /etc/systemd/system.conf.d/99-omarchy-nofile.conf \
        /etc/systemd/user.conf.d/99-omarchy-nofile.conf
