# Setup user theme folder
mkdir -p ~/.config/omarchy/themes

# Set initial theme. Offline ISO installs only need the user's theme files and
# symlinks seeded; there is no running desktop/session bus in the chroot, so
# skip shell IPC, dconf, app retint hooks, and background transition work.
if install_mode_is offline; then
  OMARCHY_THEME_OFFLINE=1 OMARCHY_THEME_SKIP_BACKGROUND=1 omarchy-theme-set "Tokyo Night"
else
  omarchy-theme-set "Tokyo Night"
fi
rm -rf ~/.config/chromium/SingletonLock # otherwise archiso will own the chromium singleton
omarchy-theme-set-pi --activate

# Set specific app links for current theme
mkdir -p ~/.config/btop/themes
ln -snf ~/.config/omarchy/current/theme/btop.theme ~/.config/btop/themes/current.theme
