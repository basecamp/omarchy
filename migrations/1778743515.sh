echo "Flip from waybar + mako to omarchy-shell (quickshell-backed bar and notifications)"

omarchy-pkg-add quickshell

# mako is replaced by the omarchy-shell notification plugin.
pkill -x mako 2>/dev/null || true
systemctl --user disable --now mako.service 2>/dev/null || true
omarchy-pkg-drop mako
rm -rf ~/.config/mako
rm -f ~/.local/state/omarchy/toggles/mako.ini

# waybar is replaced by the omarchy-shell bar plugin
pkill -x waybar 2>/dev/null || true
omarchy-pkg-drop waybar
if [[ -d ~/.config/waybar ]]; then
  mv ~/.config/waybar "$HOME/.config/waybar.omarchy-shell.bak.$(date +%s)"
fi
rm -f ~/.local/state/omarchy/toggles/waybar-off

omarchy-restart-shell
