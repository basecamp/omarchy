echo "Fix hyprlock PAM config (missing account/session sections cause freeze on wake)"

if [[ ! -f /etc/pam.d/hyprlock ]] || ! grep -qE "^(account|session)" /etc/pam.d/hyprlock; then
  sudo install -o root -g root -m 0644 "$OMARCHY_PATH/default/pam.d/hyprlock" /etc/pam.d/hyprlock
fi
