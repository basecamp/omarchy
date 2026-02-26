echo "Configuring kernel performance parameters..."
sudo mkdir -p /etc/sysctl.d

sudo tee -a /etc/sysctl.d/99-sysctl.conf >/dev/null <<'EOF'

# Network optimizations for Docker, databases, and web applications
net.core.somaxconn=65536
net.core.netdev_max_backlog=5000
net.ipv4.tcp_max_syn_backlog=8192
net.core.default_qdisc=fq
net.ipv4.tcp_fastopen=3

# Memory management - slightly reduce swappiness
vm.swappiness=30

# File system optimizations for development workloads
fs.inotify.max_user_watches=524288
fs.file-max=2097152

# Process limits that prevent common development issues
kernel.pid_max=4194304
EOF

echo "Configuring systemd resource limits..."
sudo mkdir -p /etc/systemd/system.conf.d
sudo tee /etc/systemd/system.conf.d/99-omarchy-limits.conf >/dev/null <<'EOF'
[Manager]
DefaultLimitNOFILESoft=65536
DefaultLimitNOFILE=524288
DefaultLimitNPROC=32768
EOF

sudo systemctl daemon-reload

echo "System performance optimizations configured successfully"
