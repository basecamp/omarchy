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

# Clone and patch PKGBUILD to disable browser support (CEF not available for ARM)
echo "Cloning obs-studio-git from AUR..."
BUILD_DIR=$(mktemp -d)
cd "$BUILD_DIR"

if git clone https://aur.archlinux.org/obs-studio-git.git 2>/dev/null; then
  cd obs-studio-git

  echo "Patching PKGBUILD to disable browser support (CEF unavailable on ARM)..."
  # Disable browser plugin and remove CEF dependency
  sed -i 's/-DENABLE_BROWSER=ON/-DENABLE_BROWSER=OFF/g' PKGBUILD
  # Remove CEF from source array to skip x86_64 download
  sed -i '/^source=/,/^[^)]/{/cef_binary/d}' PKGBUILD
  # Remove CEF from sha256sums
  sed -i '/^sha256sums=/,/^[^)]/{/SKIP/d; /^\s*"[a-f0-9]\{64\}"/d}' PKGBUILD

  echo "Building OBS Studio without browser support..."
  makepkg -si --noconfirm --needed --ignorearch

  cd /
  rm -rf "$BUILD_DIR"
  echo "OBS Studio installed successfully (browser sources disabled on ARM)"
else
  echo "Failed to clone obs-studio-git, trying GitHub fallback..."
  rm -rf "$BUILD_DIR"
  "$OMARCHY_PATH/bin/omarchy-aur-install" obs-studio-git
fi
