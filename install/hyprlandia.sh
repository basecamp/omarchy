yay -S --noconfirm --needed \
  hyprland hyprshot hyprpicker hyprlock hypridle polkit-gnome hyprland-qtutils \
  wofi waybar mako swaybg \
  xdg-desktop-portal-hyprland xdg-desktop-portal-gtk

# Start Hyprland on first session
cat <<EOF >~/.bash_profile
if [[ -z \$DISPLAY && \$(tty) == /dev/tty1 ]] ; then
  if [ -r ~/.config/hypr/hyprland-custom.conf ] ; then
    exec Hyprland -c ~/.config/hypr/hyprland-custom.conf
  else
    exec Hyprland
  fi
fi
EOF
