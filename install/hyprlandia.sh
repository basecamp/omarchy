# Install Hyprland and related packages on Fedora
# Note: Some packages may need to be installed from Copr repositories or built from source

sudo dnf copr enable -y solopasha/hyprland

sudo dnf install -y \
  hyprland hyprshot hyprpicker hyprlock hypridle waybar wofi mako swaybg \
  xdg-desktop-portal-hyprland xdg-desktop-portal-gtk

# Note: hyprpolkitagent and hyprland-qtutils may not be available in Fedora repos
# These may need to be compiled from source or installed via Flatpak

# Start Hyprland on first session
echo "[[ -z \$DISPLAY && \$(tty) == /dev/tty1 ]] && exec Hyprland" >~/.bash_profile
