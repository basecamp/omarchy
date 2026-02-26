# Select keyboard layout during first-time installation
# Must be sourced (not run_logged) since gum filter needs stdin

marker="$HOME/.local/state/omarchy/keyboard-layout-selected"

# Skip if already selected (re-install)
if [[ -f "$marker" ]]; then
  echo "Keyboard layout: already selected"
  return 0
fi

conf="/etc/vconsole.conf"
current_keymap=""
if [[ -f "$conf" ]] && grep -q '^KEYMAP=' "$conf"; then
  current_keymap=$(grep '^KEYMAP=' "$conf" | cut -d= -f2 | tr -d '"')
fi

echo "Current console keymap: ${current_keymap:-us (default)}"

if ! gum confirm "Change keyboard layout?"; then
  echo "Keyboard layout: keeping ${current_keymap:-us}"
  mkdir -p "$(dirname "$marker")"
  touch "$marker"
  return 0
fi

selected=$(localectl list-keymaps | gum filter --height 20 --header "Select keyboard layout" || true)

if [[ -z "$selected" ]]; then
  echo "Keyboard layout: no selection made, keeping ${current_keymap:-us}"
  mkdir -p "$(dirname "$marker")"
  touch "$marker"
  return 0
fi

echo "Setting keyboard layout to: $selected"

# Try localectl first (auto-maps KEYMAP to XKBLAYOUT/XKBVARIANT)
# Falls back to direct vconsole.conf edit in chroot where D-Bus isn't available
localectl_output=""
if localectl_output=$(sudo localectl set-keymap "$selected" 2>&1); then
  echo "Keyboard layout set via localectl"
else
  if echo "$localectl_output" | grep -qiE 'Failed to (connect to bus|create bus connection)'; then
    echo "localectl unavailable (chroot), updating vconsole.conf directly"
    if [[ -f "$conf" ]]; then
      sudo sed -i '/^KEYMAP=/d' "$conf"
    fi
    echo "KEYMAP=$selected" | sudo tee -a "$conf" >/dev/null
  else
    echo "Error: failed to set keyboard layout via localectl:" >&2
    echo "$localectl_output" >&2
    return 1
  fi
fi

# Load keymap immediately so the rest of the install uses it
sudo loadkeys "$selected" 2>/dev/null || true

mkdir -p "$(dirname "$marker")"
touch "$marker"
echo "Keyboard layout: $selected"
