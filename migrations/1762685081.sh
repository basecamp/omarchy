echo "Update hyprlock placeholder text based on fingerprint setup status"

cp ~/.config/hypr/hyprlock.conf ~/.config/hypr/hyprlock.conf.bak.$(date +%s)

# Check if fprintd is installed and has enrolled fingerprints
if command -v fprintd-list &>/dev/null && fprintd-list "$USER" 2>/dev/null | grep -q "Fingerprints for user"; then
  echo "Fingerprint detected, updating placeholder text with fingerprint icon"
  sed -i 's/placeholder_text = .*/placeholder_text = <span> Enter Password 󰈷 <\/span>/' ~/.config/hypr/hyprlock.conf
else
  echo "No fingerprint enrolled, updating placeholder text without fingerprint icon"
  sed -i 's/placeholder_text = .*/placeholder_text = Enter Password/' ~/.config/hypr/hyprlock.conf
fi
