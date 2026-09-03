echo "Pin Signal password store to gnome-libsecret (prevents profile key fallback on Hyprland)"

# Signal is an Electron app and uses the same os_crypt machinery as Chromium
# browsers. On Hyprland the xdg-desktop-portal Secret backend has no provider,
# so without a pin Signal falls back to the 'basic' store and a profile whose
# DB key was stored under gnome-libsecret can no longer be decrypted (the
# profile is unrecoverable without the original keyring secret). Migration
# 1784508556 pins the browsers; this is the same class for the app Omarchy
# installs itself. A user-chosen --password-store line wins, as it does for
# browsers.
flags_file="$HOME/.config/signal-desktop-flags.conf"
if grep -q -- '--password-store=' "$flags_file" 2>/dev/null; then
  exit 0
fi

mkdir -p "$HOME/.config"
[[ -n $(tail -c1 "$flags_file" 2>/dev/null) ]] && echo >>"$flags_file"
echo '--password-store=gnome-libsecret' >>"$flags_file"
