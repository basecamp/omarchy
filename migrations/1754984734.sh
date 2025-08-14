echo "Configure Docker to use the host's DNS resolver"

# If the daemon configuration has been changed since we wrote it, leave it as-is
ORIGINAL_CONFIG='{"log-driver":"json-file","log-opts":{"max-size":"10m","max-file":"5"}}'

NEW_CONFIG='{
    "log-driver": "json-file",
    "log-opts": { "max-size": "10m", "max-file": "5" },
    "dns": ["172.17.0.1"],
    "bip": "172.17.0.1/16"
}'

if grep -Fq "$ORIGINAL_CONFIG" /etc/docker/daemon.json 2>/dev/null; then
  echo "$NEW_CONFIG" | sudo tee /etc/docker/daemon.json >/dev/null
fi

# Expose systemd-resolved to our Docker network
echo -e '[Resolve]\nDNSStubListenerExtra=172.17.0.1' | sudo tee /etc/systemd/resolved.conf.d/20-docker-dns.conf >/dev/null

sudo systemctl restart systemd-resolved
sudo systemctl restart docker
