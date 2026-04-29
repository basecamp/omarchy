echo "Installing OBS Studio for ARM..."

# Check if OBS is already installed
if command -v obs &>/dev/null; then
  echo "OBS Studio already installed, skipping"
  return 0
fi

# Install dependencies that the PKGBUILD needs (ARM-compatible subset)
# The PKGBUILD's depends/makedepends include x86-only packages (libvpl, ffnvcodec-headers)
# that we must remove, so we pre-install the ARM-compatible ones and patch the PKGBUILD
sudo pacman -S --needed --noconfirm \
  base-devel git cmake ninja pkgconf \
  curl ffmpeg jansson libdatachannel libpipewire librist \
  libxcomposite mbedtls pciutils qrcodegencpp-cmake qt6-svg rnnoise simde speexdsp \
  asio extra-cmake-modules libfdk-aac luajit nlohmann-json python \
  qt6-wayland sndio swig uthash vlc wayland websocketpp x264 xdg-desktop-portal

# Verify FFmpeg libraries are findable via pkg-config (cmake depends on this)
if ! pkg-config --exists libavformat libavutil libswscale libswresample 2>/dev/null; then
  echo "FFmpeg pkg-config modules not found, reinstalling ffmpeg..."
  sudo pacman -S --noconfirm ffmpeg
  if ! pkg-config --exists libavformat libavutil libswscale libswresample 2>/dev/null; then
    echo "ERROR: FFmpeg libraries still not findable after reinstall"
    echo "  pkg-config --list-all | grep -i av:"
    pkg-config --list-all 2>/dev/null | grep -i 'av\|swscale\|swresample' || true
    return 1
  fi
fi
echo "FFmpeg verified: $(pkg-config --modversion libavformat) (avformat)"

# Clone and patch PKGBUILD for ARM
echo "Cloning obs-studio-git from AUR..."
BUILD_DIR=$(mktemp -d)
cd "$BUILD_DIR"

if git clone https://aur.archlinux.org/obs-studio-git.git 2>/dev/null; then
  cd obs-studio-git

  echo "Patching PKGBUILD for ARM (disabling browser, removing x86-only deps)..."

  # 1. Disable browser plugin (CEF not available for ARM)
  sed -i 's/-DENABLE_BROWSER=ON/-DENABLE_BROWSER=OFF/g' PKGBUILD

  # 2. Remove the _source_cef function call and definition (CEF is x86-only)
  #    The PKGBUILD now builds source arrays in functions: _source_main() and _source_cef()
  #    Remove the _source_cef call so it never runs
  sed -i '/^_source_cef$/d' PKGBUILD

  # 3. Remove x86-only packages from depends/makedepends
  #    - libvpl: Intel Video Processing Library (x86-only)
  #    - ffnvcodec-headers: NVIDIA codec headers (x86-only)
  sed -i "/'libvpl'/d" PKGBUILD
  sed -i "/'ffnvcodec-headers'/d" PKGBUILD

  # 4. Add aarch64 to supported architectures
  sed -i 's/arch=("i686" "x86_64")/arch=("i686" "x86_64" "aarch64")/' PKGBUILD

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
