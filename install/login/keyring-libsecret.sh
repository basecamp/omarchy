# Ensure keyring + libsecret packages are installed for applications (VSCode, Element, 1Password, etc.)
if ! command -v gnome-keyring &>/dev/null || ! yay -Qq libsecret &>/dev/null; then
  yay -S --noconfirm --needed gnome-keyring libsecret
fi

# Configure PAM to start gnome-keyring on login (idempotent & inserted after last auth/session block)
if [ -f /etc/pam.d/login ]; then
  pam_file=/etc/pam.d/login

  # Insert auth line after last existing auth line
  if ! grep -q '^auth\s\+optional\s\+pam_gnome_keyring.so' "$pam_file"; then
    sudo awk 'NR==1{lines[NR]=$0; next}{lines[NR]=$0} /^auth[[:space:]]/ { last_auth=NR } END { for(i=1;i<=NR;i++){ print lines[i]; if(i==last_auth){ print "auth       optional     pam_gnome_keyring.so" } } if(NR==0){ print "auth       optional     pam_gnome_keyring.so" } }' "$pam_file" > /tmp/omarchy.pam && sudo mv /tmp/omarchy.pam "$pam_file"
  fi

  # Insert session line after last existing session line (or at end if none)
  if ! grep -q '^session\s\+optional\s\+pam_gnome_keyring.so\s\+auto_start' "$pam_file"; then
    sudo awk '{lines[NR]=$0} /^session[[:space:]]/ { last_session=NR } END { for(i=1;i<=NR;i++){ print lines[i]; if(i==last_session){ print "session    optional     pam_gnome_keyring.so auto_start" } } if(!last_session){ print "session    optional     pam_gnome_keyring.so auto_start" } }' "$pam_file" > /tmp/omarchy.pam && sudo mv /tmp/omarchy.pam "$pam_file"
  fi
fi

# Ensure Hyprland autostart updates DBus/systemd environment (required for keyring detection in some apps)
if ! grep -q 'dbus-update-activation-environment --systemd --all' ~/.config/hypr/autostart.conf 2>/dev/null; then
  echo 'exec-once = dbus-update-activation-environment --systemd --all' >>~/.config/hypr/autostart.conf
fi