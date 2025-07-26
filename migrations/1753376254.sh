echo "Installing omarchy-monitor-settings for Hyprland monitor control"

if ! command -v omarchy-monitor-settings &>/dev/null; then
  # Install Go if not already installed
  if ! command -v go &>/dev/null; then
    mise use -g go@latest
  fi

  # Clone and build the monitor settings application
  # TODO: Discuss where this should live
  git clone https://github.com/ryanyogan/omarchy-monitor-settings.git /tmp/omarchy-monitor-settings
  cd /tmp/omarchy-monitor-settings

  git checkout v1.1.1

  export CGO_ENABLED=0
  export GOOS=linux

  VERSION=$(git describe --tags --always --dirty 2>/dev/null || echo "dev")
  go build -ldflags "-s -w -X main.version=${VERSION}" -o omarchy-monitor-settings .

  sudo mv omarchy-monitor-settings /usr/local/bin/
  sudo chmod +x /usr/local/bin/omarchy-monitor-settings
  cd -
  rm -rf /tmp/omarchy-monitor-settings
fi
