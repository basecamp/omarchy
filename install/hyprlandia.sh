yay -S --noconfirm --needed \
  hyprland hyprshot hyprpicker hyprlock hypridle hyprpolkitagent hyprland-qtutils \
  wofi waybar mako swaybg \
  xdg-desktop-portal-hyprland xdg-desktop-portal-gtk

# Checks if nvidia gpu exist
gpu_info=$(lspci | grep -i 'nvidia')
if [ -n "$gpu_info" ]; then
    # Ask user if they want to install NVIDIA drivers
    if [ -t 0 ]; then
        read -p "NVIDIA GPU detected. Do you want to install NVIDIA drivers? (y/N) " install_nvidia
        if [[ "$install_nvidia" =~ ^[yY](es)?$ ]]; then
            source ~/.local/share/omarchy/install/nvidia
        fi
    else
        # Non-interactive mode - run nvidia script
        source ~/.local/share/omarchy/install/nvidia
    fi
fi

# Start Hyprland on first session
echo "[[ -z \$DISPLAY && \$(tty) == /dev/tty1 ]] && exec Hyprland" >~/.bash_profile
