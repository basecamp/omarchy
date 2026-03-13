echo "Add monitor auto-configuration"

# Install socat if not already present (needed for event-driven hotplug detection)
if ! command -v socat &>/dev/null; then
  sudo pacman -S --noconfirm socat
fi
