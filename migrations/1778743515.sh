echo "Flip from waybar + mako to omarchy-shell (quickshell-backed bar and notifications)"

# ---------------------------------------------------------------- packages
# Ensure quickshell is installed so omarchy-shell can launch. omarchy-pkg-add
# is a no-op if already present.
if omarchy-cmd-missing quickshell; then
  omarchy-pkg-add quickshell || true
fi

# ---------------------------------------------------------------- mako -> shell
# mako is replaced by the omarchy-shell notification plugin. Stop the running
# instance, then uninstall outright — pacman -Rns removes the .service unit
# file too, so D-Bus activation has nothing to look up afterwards.
pkill -x mako 2>/dev/null || true
systemctl --user stop    mako.service 2>/dev/null || true
systemctl --user disable mako.service 2>/dev/null || true
if omarchy-pkg-present mako; then
  sudo pacman -Rns --noconfirm mako >/dev/null 2>&1 || true
fi

# Move the old mako config aside instead of removing it. Users may have
# hand-tuned rules they want to copy forward into the new notification
# daemon's per-theme override file.
if [[ -d ~/.config/mako ]]; then
  mv ~/.config/mako "$HOME/.config/mako.omarchy-shell.bak.$(date +%s)"
fi

# Old toggle marker is no longer read.
[[ -f ~/.local/state/omarchy/toggles/mako.ini ]] && rm -f ~/.local/state/omarchy/toggles/mako.ini

# ---------------------------------------------------------------- waybar -> shell
# waybar is replaced by the omarchy-shell bar plugin. Stop the process, then
# uninstall; user config is stashed below in case they want to mine it.
pkill -x waybar 2>/dev/null || true
if omarchy-pkg-present waybar; then
  sudo pacman -Rns --noconfirm waybar >/dev/null 2>&1 || true
fi

if [[ -d ~/.config/waybar ]]; then
  mv ~/.config/waybar "$HOME/.config/waybar.omarchy-shell.bak.$(date +%s)"
fi

# Old toggle marker is no longer meaningful — autostart no longer reads it.
[[ -f ~/.local/state/omarchy/toggles/waybar-off ]] && rm -f ~/.local/state/omarchy/toggles/waybar-off

# ---------------------------------------------------------------- launch shell
# Hyprland's autostart calls omarchy-restart-shell at session start, but the
# migration also runs mid-session on `omarchy update`. Kick the shell now so
# the notification daemon and bar are live without waiting for a relog.
if omarchy-cmd-present omarchy-restart-shell; then
  omarchy-restart-shell >/dev/null 2>&1 || true
fi
