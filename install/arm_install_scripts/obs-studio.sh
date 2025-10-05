echo "Installing OBS Studio for ARM..."

# Check if OBS is already installed
if command -v obs &>/dev/null; then
  echo "OBS Studio already installed, skipping"
  return 0
fi

# Install dependencies
sudo pacman -S --needed --noconfirm base-devel git cmake qt6-base qt6-svg \
  qt6-multimedia qt6-5compat ffmpeg libx11 libxcomposite \
  libxrandr libxcb wayland-protocols libxkbcommon alsa-lib \
  libv4l dav1d

# Clone and build from AUR
git clone https://aur.archlinux.org/obs-studio-git.git
cd obs-studio-git
makepkg -si --noconfirm --ignorearch

# Clean up
cd ..
rm -rf obs-studio-git

cd ~

echo "OBS Studio installed successfully"
