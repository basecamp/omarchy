# Setup user theme folder
mkdir -p ~/.config/omarchy/themes

if [[ ${OMARCHY_SETUP_CONTEXT:-runtime} == "iso-chroot" ]]; then
  OMARCHY_THEME_HEADLESS=1 omarchy-theme-set "Tokyo Night"
else
  omarchy-theme-set "Tokyo Night"
fi

rm -rf ~/.config/chromium/SingletonLock
omarchy-theme-set-pi --activate

mkdir -p ~/.config/btop/themes
ln -snf ~/.config/omarchy/current/theme/btop.theme ~/.config/btop/themes/current.theme
