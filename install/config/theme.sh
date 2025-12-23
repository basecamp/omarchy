# Set links for Nautilus action icons
sudo ln -snf /usr/share/icons/Adwaita/symbolic/actions/go-previous-symbolic.svg /usr/share/icons/Yaru/scalable/actions/go-previous-symbolic.svg
sudo ln -snf /usr/share/icons/Adwaita/symbolic/actions/go-next-symbolic.svg /usr/share/icons/Yaru/scalable/actions/go-next-symbolic.svg

# Setup user theme folder
mkdir -p ~/.config/omarchy/themes

# Set initial theme
omarchy-theme-set "Osaka Jade"

# Set specific app links for current theme
mkdir -p ~/.config/btop/themes
ln -snf ~/.config/omarchy/current/theme/btop.theme ~/.config/btop/themes/current.theme

mkdir -p ~/.config/mako
ln -snf ~/.config/omarchy/current/theme/mako.ini ~/.config/mako/config
