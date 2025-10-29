echo "Setup PAM configuration for Hyprlock screen locker"

# Create the file if it doesn't exist
if [[ ! -f /etc/pam.d/hyprlock ]]; then
  sudo mkdir -p /etc/pam.d
  sudo tee /etc/pam.d/hyprlock >/dev/null <<'EOF'
# Omarchy PAM fix for Hyprlock (Arch-based)
auth       include        system-local-login
account    include        system-local-login
password   include        system-local-login
session    include        system-local-login
EOF
  sudo chmod 644 /etc/pam.d/hyprlock
else
  # File exists, ensure it has the correct entries
  if ! grep -q "auth.*include.*system-local-login" /etc/pam.d/hyprlock; then
    echo "auth       include        system-local-login" | sudo tee -a /etc/pam.d/hyprlock >/dev/null
  fi
  if ! grep -q "account.*include.*system-local-login" /etc/pam.d/hyprlock; then
    echo "account    include        system-local-login" | sudo tee -a /etc/pam.d/hyprlock >/dev/null
  fi
  if ! grep -q "password.*include.*system-local-login" /etc/pam.d/hyprlock; then
    echo "password   include        system-local-login" | sudo tee -a /etc/pam.d/hyprlock >/dev/null
  fi
  if ! grep -q "session.*include.*system-local-login" /etc/pam.d/hyprlock; then
    echo "session    include        system-local-login" | sudo tee -a /etc/pam.d/hyprlock >/dev/null
  fi
fi
