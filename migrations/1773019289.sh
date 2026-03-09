echo "Fix hyprlock PAM config (missing account/session sections cause freeze on wake)"

if [[ -f /etc/pam.d/hyprlock ]] && ! grep -q "^account" /etc/pam.d/hyprlock; then
  sudo cp -p "$OMARCHY_PATH/default/pam.d/hyprlock" /etc/pam.d/hyprlock
fi
