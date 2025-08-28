#!/bin/bash

# Migration: Ensure gnome-keyring + libsecret + PAM + autostart DBus environment for keyring-backed apps (Issue #1015)

# Packages
if ! yay -Qq gnome-keyring &>/dev/null || ! yay -Qq libsecret &>/dev/null; then
  echo "Installing gnome-keyring and libsecret (required for secure storage in VSCode, Element, etc.)"
  yay -S --noconfirm --needed gnome-keyring libsecret || true
fi

# PAM login (same structure as config script: append after last matching block)
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

# Hypr autostart
mkdir -p ~/.config/hypr
if ! grep -q 'dbus-update-activation-environment --systemd --all' ~/.config/hypr/autostart.conf 2>/dev/null; then
  echo "Adding dbus-update-activation-environment to Hypr autostart"
  echo 'exec-once = dbus-update-activation-environment --systemd --all' >>~/.config/hypr/autostart.conf
fi

