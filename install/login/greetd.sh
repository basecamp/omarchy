# Configure greetd with DedSec greeter (replaces SDDM)
# Falls back to SDDM if quickshell is not available.

# Safety check: if quickshell didn't install, keep SDDM and skip greeter setup
if ! command -v quickshell &>/dev/null; then
  echo "WARNING: quickshell not found -- falling back to SDDM. DedSec greeter will not be available."
  sudo systemctl enable sddm.service 2>/dev/null || true
  return 0 2>/dev/null || exit 0
fi

# Copy greeter QML project to /opt/dedsec/
sudo mkdir -p /opt/dedsec
sudo cp -rLf "$HOME/.local/share/omarchy/default/dedsec-greeter"/* /opt/dedsec/

# Fix Common directory symlinks (git on Windows stores symlinks as plain text files)
# These must be actual symlinks for QML module resolution to work
sudo rm -f /opt/dedsec/Greeter/Common /opt/dedsec/Bar/Common
sudo ln -sf ../Common /opt/dedsec/Greeter/Common
sudo ln -sf ../Common /opt/dedsec/Bar/Common

# Create config directory
sudo mkdir -p /etc/dedsec

# Gather real system info for greeter config
_real_name=$(getent passwd "$USER" 2>/dev/null | cut -d: -f5 | cut -d, -f1)
[[ -z "$_real_name" ]] && _real_name="$USER"

_operator_id="DS-$(head -c 4 /etc/machine-id 2>/dev/null | tr 'a-f' 'A-F' || echo '0000')"

_access_class="SEC_OPS"
if id -nG "$USER" 2>/dev/null | grep -qw wheel; then
  _access_class="ROOT_OPS"
fi

_hostname=$(hostname 2>/dev/null || echo "localhost")

# Generate greeter config if not exists
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

# Copy minimal Hyprland config for greeter session
sudo cp -f "$HOME/.local/share/omarchy/default/dedsec-greeter/Greeter/examples/greeter.hyprland.conf" /etc/dedsec/

# Configure greetd -- greeter runs inside a minimal Hyprland session
sudo mkdir -p /etc/greetd
sudo tee /etc/greetd/config.toml > /dev/null << 'EOF'
[terminal]
vt = 1

[default_session]
command = "Hyprland --config /etc/dedsec/greeter.hyprland.conf"
user = "greeter"
EOF

# Ensure greeter user exists (greetd package creates it, but verify)
if ! id greeter &>/dev/null; then
  sudo useradd -r -s /bin/bash -d /opt/dedsec greeter 2>/dev/null || true
fi

# Greeter user needs video + input access for Hyprland
sudo usermod -aG video,input greeter 2>/dev/null || true

# Ensure greeter user can read the greeter files and write to its runtime
sudo chown -R greeter:greeter /opt/dedsec 2>/dev/null || true
sudo chmod -R 755 /opt/dedsec 2>/dev/null || true

# Greeter needs to read the config
sudo chmod 644 /etc/dedsec/greeter.config.json 2>/dev/null || true
sudo chmod 644 /etc/dedsec/greeter.hyprland.conf 2>/dev/null || true

# Disable SDDM, enable greetd
sudo systemctl disable sddm.service 2>/dev/null || true
sudo systemctl enable greetd.service
