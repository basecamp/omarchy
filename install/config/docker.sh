# Configure Docker daemon:
# - limit log size to avoid running out of disk
# - use host's DNS resolver
# - optimize MTU for Tailscale/WireGuard VPNs (1280 bytes)
# - increase ulimits for better container performance
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{
    "log-driver": "json-file",
    "log-opts": { "max-size": "10m", "max-file": "5" },
    "dns": ["172.17.0.1"],
    "bip": "172.17.0.1/16",
    "mtu": 1280,
    "default-network-opts": {
        "bridge": {
            "com.docker.network.driver.mtu": "1280"
        }
    },
    "default-ulimits": {
        "nofile": {
            "Name": "nofile",
            "Hard": 65536,
            "Soft": 65536
        },
        "nproc": {
            "Name": "nproc",
            "Hard": 65536,
            "Soft": 65536
        }
    }
}
EOF

# Expose systemd-resolved to our Docker network
sudo mkdir -p /etc/systemd/resolved.conf.d
echo -e '[Resolve]\nDNSStubListenerExtra=172.17.0.1' | sudo tee /etc/systemd/resolved.conf.d/20-docker-dns.conf >/dev/null
sudo systemctl restart systemd-resolved

# Start Docker automatically
sudo systemctl enable docker

# Give this user privileged Docker access
sudo usermod -aG docker ${USER}

# Prevent Docker from preventing boot for network-online.target
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/no-block-boot.conf <<'EOF'
[Unit]
DefaultDependencies=no
EOF

sudo systemctl daemon-reload
