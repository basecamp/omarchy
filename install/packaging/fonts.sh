# Omarchy logo in a font for Waybar use
mkdir -p ~/.local/share/fonts
cp ~/.local/share/omarchy/config/omarchy.ttf ~/.local/share/fonts/

# Microsoft fonts for Vivaldi
omarchy-pkg-aur-install ttf-ms-fonts

fc-cache
