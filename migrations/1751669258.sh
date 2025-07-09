echo "Ensure Docker config is set"
if [[ ! -f /etc/docker/daemon.json ]]; then
  sudo mkdir -p /etc/docker
  echo '{"log-driver":"json-file","log-opts":{"max-size":"10m","max-file":"5"}}' | sudo tee /etc/docker/daemon.json
fi
