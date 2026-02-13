echo "Replace SDDM with greetd + DedSec greeter, install Quickshell"

# Install greetd and quickshell (quickshell is now in official extra repo)
omarchy-pkg-add greetd quickshell

# Deploy greeter files to /opt/dedsec/
sudo mkdir -p /opt/dedsec
sudo cp -rLf ~/.local/share/omarchy/default/dedsec-greeter/* /opt/dedsec/

# Fix Common directory symlinks (git on Windows stores symlinks as plain text)
sudo rm -f /opt/dedsec/Greeter/Common /opt/dedsec/Bar/Common
sudo ln -sf ../Common /opt/dedsec/Greeter/Common
sudo ln -sf ../Common /opt/dedsec/Bar/Common

# Ensure greeter user exists and has video access
if ! id greeter &>/dev/null; then
  sudo useradd -r -s /bin/bash -d /opt/dedsec greeter 2>/dev/null || true
fi
sudo usermod -aG video,input greeter 2>/dev/null || true
sudo chown -R greeter:greeter /opt/dedsec 2>/dev/null || true
sudo chmod -R 755 /opt/dedsec 2>/dev/null || true

# Create config directory and generate default config
sudo mkdir -p /etc/dedsec

# Gather real system info
_real_name=$(getent passwd "$USER" 2>/dev/null | cut -d: -f5 | cut -d, -f1)
[[ -z "$_real_name" ]] && _real_name="$USER"
_operator_id="DS-$(head -c 4 /etc/machine-id 2>/dev/null | tr 'a-f' 'A-F' || echo '0000')"
_access_class="SEC_OPS"
if id -nG "$USER" 2>/dev/null | grep -qw wheel; then
  _access_class="ROOT_OPS"
fi
_hostname=$(hostname 2>/dev/null || echo "localhost")

if [[ ! -f /etc/dedsec/greeter.config.json ]]; then
  cat <<EOF | sudo tee /etc/dedsec/greeter.config.json > /dev/null
{
  "user": "$USER",
  "monitor": "",
  "fontFamily": "JetBrainsMono Nerd Font",
  "animations": "all",
  "identity": {
    "id": "$_operator_id",
    "class": "$_access_class",
    "fullName": "$_real_name"
  },
  "systemInfo": {
    "env": "$_hostname",
    "node": "$_hostname"
  },
  "modes": {
    "greetd": {
      "launch": ["uwsm", "start", "hyprland.desktop"],
      "exit": ["uwsm", "stop"]
    }
  }
}
EOF
fi

# Copy greeter Hyprland config and set permissions
sudo cp -f ~/.local/share/omarchy/default/dedsec-greeter/Greeter/examples/greeter.hyprland.conf /etc/dedsec/
sudo chmod 644 /etc/dedsec/greeter.config.json 2>/dev/null || true
sudo chmod 644 /etc/dedsec/greeter.hyprland.conf 2>/dev/null || true

# Configure greetd
sudo mkdir -p /etc/greetd
sudo tee /etc/greetd/config.toml > /dev/null << 'EOF'
[terminal]
vt = 1

[default_session]
command = "Hyprland --config /etc/dedsec/greeter.hyprland.conf"
user = "greeter"
EOF

# Only switch to greetd if quickshell actually installed successfully
if command -v quickshell &>/dev/null; then
  sudo systemctl disable sddm.service 2>/dev/null || true
  sudo systemctl enable greetd.service
else
  echo "WARNING: quickshell not found -- keeping SDDM. DedSec greeter will not be available."
fi

# Refresh the lock screen and hypridle configs
omarchy-refresh-hyprland
