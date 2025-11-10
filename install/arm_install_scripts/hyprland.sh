#!/bin/bash

# Detect if script is being sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Script is being executed directly (bash hyprland.sh)
  SCRIPT_MODE="execute"
  script_exit() { exit "$1"; }
else
  # Script is being sourced (source hyprland.sh)
  SCRIPT_MODE="source"
  script_exit() { return "$1"; }
fi

# Detect script location for both sourced and direct execution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set OMARCHY_INSTALL if not already set (for direct execution testing)
if [[ -z "${OMARCHY_INSTALL:-}" ]]; then
  # Go up one directory from arm_install_scripts to get install directory
  OMARCHY_INSTALL="$(dirname "$SCRIPT_DIR")"
  echo "Detected OMARCHY_INSTALL: $OMARCHY_INSTALL"
fi

# Set up build logging
BUILD_LOG="/tmp/hyprland-build.log"
# Remove old log to avoid confusion from previous runs
rm -f "$BUILD_LOG"
# Redirect all output to both stdout and the log file (overwrite, not append)
exec > >(tee "$BUILD_LOG") 2>&1
echo "==================================="
echo "Hyprland ARM Build Log"
echo "Started: $(date)"
echo "==================================="
echo ""

# Function to upload build log on failure
upload_build_log() {
  echo ""
  echo "Uploading build log to 0x0.st for debugging..."

  # Add system info to the log
  {
    echo ""
    echo "==================================="
    echo "SYSTEM INFORMATION"
    echo "==================================="
    echo "Architecture: $(uname -m)"
    echo "Kernel: $(uname -r)"
    echo "GCC Version: $(gcc --version | head -1)"
    echo "Date: $(date)"
    echo ""
  } >> "$BUILD_LOG"

  # Upload with 60 second timeout
  URL=$(curl --max-time 60 -s -F "file=@$BUILD_LOG" -Fexpires=24 https://0x0.st 2>/dev/null)

  if [ -n "$URL" ] && [[ "$URL" =~ ^https?:// ]]; then
    echo ""
    echo "✓ Build log uploaded successfully!"
    echo ""
    echo "Share this URL for debugging:"
    echo "  -----------------------"
    echo "  $URL"
    echo "  -----------------------"
    echo ""
    echo "This link will expire in 24 hours."
    echo ""
  else
    echo "Failed to upload build log automatically."
    echo "Build log saved at: $BUILD_LOG"
    echo "You can manually upload with: curl -F \"file=@$BUILD_LOG\" https://0x0.st"
    echo ""
  fi
}

# Build and install Hyprland from source for ARM with GCC 14 compatibility
#
# Background:
# - ARM repos have Hyprland 0.49.0, but Omarchy x86 uses 0.51+ (configs incompatible)
# - Hyprland 0.51+ uses #embed directive (requires GCC 15+)
# - Hyprland 0.51+ has stricter template deduction in string concatenation (GCC 14 fails)
# - Hyprland 0.51+ uses C++23 insert_range() API (GCC 14's libstdc++ lacks it)
# - x86_64 has GCC 15.2.1, ARM has GCC 14.2.1 (can't build 0.51+ without patches)
#
# Solution:
# - Use Arch Linux's official PKGBUILD approach (release tarball, CMAKE_SKIP_RPATH=ON)
# - Patch #embed directive → inline string (matches 0.49.0 approach, works on GCC 14)
# - Patch string concatenations → explicit type conversions (GCC 14 template deduction)
# - Patch ternary operators → explicit nullptr cast (GCC 14 type deduction)
# - Patch insert_range() → ranges::copy() (C++23 → C++20 compatibility)
# - Ensures ARM uses same Hyprland version as x86 for config compatibility

echo "Building Hyprland from source for ARM..."

# Check if Hyprland 0.51+ is already installed
if command -v Hyprland &>/dev/null; then
  INSTALLED_VERSION=$(Hyprland --version 2>&1 | grep -oP 'Hyprland, built from branch .+ at commit .+ \(v\K[0-9.]+' || echo "unknown")

  if [[ "$INSTALLED_VERSION" != "unknown" ]] && [[ "$INSTALLED_VERSION" =~ ^0\.(5[0-9]|[6-9][0-9]) ]]; then
    echo "Hyprland $INSTALLED_VERSION already installed (0.50+), skipping"
    script_exit 0
  else
    echo "Hyprland $INSTALLED_VERSION detected (need 0.50+ for config compatibility)"
    echo "Rebuilding from source with ARM patches..."
    # Remove old version if present
    if pacman -Qi hyprland &>/dev/null; then
      echo "Removing repository version..."
      sudo pacman -Rdd --noconfirm hyprland 2>/dev/null || true
    fi
  fi
fi

# Install build dependencies (matches Arch Linux PKGBUILD makedepends + depends)
echo "Installing build dependencies..."
sudo pacman -S --needed --noconfirm \
  base-devel cmake meson ninja glaze \
  aquamarine cairo gcc-libs glib2 glslang hyprcursor hyprgraphics hyprlang hyprutils \
  libdisplay-info libdrm libglvnd libinput libliftoff libx11 libxcb libxcomposite \
  libxcursor libxfixes libxkbcommon libxrender mesa pango pixman re2 seatd \
  systemd-libs tomlplusplus wayland wayland-protocols xcb-proto xcb-util \
  xcb-util-errors xcb-util-keysyms xcb-util-renderutil xcb-util-wm xorg-xwayland \
  hyprland-protocols vulkan-headers xorgproto

# Use the same approach as Arch Linux official PKGBUILD
# Download release tarball instead of git clone (includes properly bundled submodules)
HYPR_VERSION="0.52.1"
TARBALL_URL="https://github.com/hyprwm/Hyprland/releases/download/v${HYPR_VERSION}/source-v${HYPR_VERSION}.tar.gz"
TARBALL_NAME="hyprland-source-v${HYPR_VERSION}.tar.gz"

# Create cache directory for tarballs
CACHE_DIR="${HOME}/.cache/omarchy/hyprland"
mkdir -p "$CACHE_DIR"

# Check if tarball already downloaded
TARBALL_PATH="${CACHE_DIR}/${TARBALL_NAME}"
if [[ -f "$TARBALL_PATH" ]]; then
  echo "Using cached tarball: ${TARBALL_NAME}"
else
  echo "Downloading Hyprland ${HYPR_VERSION} release tarball..."
  if ! curl -fsSL "$TARBALL_URL" -o "$TARBALL_PATH"; then
    echo "Failed to download Hyprland release tarball"
    rm -f "$TARBALL_PATH"
    script_exit 1
  fi
  echo "✓ Downloaded to cache: ${TARBALL_PATH}"
fi

# Create temporary build directory
BUILD_DIR=$(mktemp -d)
cd "$BUILD_DIR"

echo "Extracting tarball..."
if ! tar -xzf "$TARBALL_PATH"; then
  echo "Failed to extract tarball"
  rm -rf "$BUILD_DIR"
  script_exit 1
fi

cd "hyprland-source"

# Apply Arch Linux's prepare() modifications
echo "Applying Arch Linux build configuration..."
# Add CMAKE_SKIP_RPATH=ON to release target (matches Arch PKGBUILD)
sed -i -e '/^release:/{n;s/-D/-DCMAKE_SKIP_RPATH=ON -D/}' Makefile

# Remove version script (workaround for Arch Linux issue #15)
rm -fv scripts/generateVersion.sh

echo "✓ Arch Linux modifications applied"

# Apply GCC 14 compatibility patch (replace #embed with inline string)
echo "Applying GCC 14 compatibility patch (#embed requires GCC 15+)..."
PATCH_SCRIPT="$OMARCHY_INSTALL/arm_install_scripts/generate-hyprland-no-embed-patch.sh"
if [[ -f "$PATCH_SCRIPT" ]]; then
  if bash "$PATCH_SCRIPT"; then
    echo "✓ GCC 14 compatibility patch applied"
  else
    echo "ERROR: Failed to apply GCC 14 compatibility patch"
    echo "  #embed directive requires GCC 15+ (ARM has GCC 14.2.1)"
    rm -rf "$BUILD_DIR"
    script_exit 1
  fi
else
  echo "WARNING: Patch script not found at $PATCH_SCRIPT"
  echo "Build will likely fail with '#embed' directive error"
fi

# Apply GCC 14 compatibility fixes (template deduction, ternary operators, C++23 APIs)
echo "Applying GCC 14 compatibility fixes..."
GCC14_FIX_SCRIPT="$OMARCHY_INSTALL/arm_install_scripts/fix-hyprland-string-concat.sh"
if [[ -f "$GCC14_FIX_SCRIPT" ]]; then
  if bash "$GCC14_FIX_SCRIPT"; then
    echo "✓ GCC 14 compatibility fixes applied"
  else
    echo "ERROR: Failed to apply GCC 14 compatibility fixes"
    echo "  GCC 14 has stricter type deduction rules than GCC 15"
    echo "  GCC 14's libstdc++ lacks C++23 standard library features"
    rm -rf "$BUILD_DIR"
    script_exit 1
  fi
else
  echo "WARNING: GCC 14 fix script not found at $GCC14_FIX_SCRIPT"
  echo "Build may fail with type deduction errors or C++23 API errors"
fi

echo "✓ Build configuration complete (Arch PKGBUILD + GCC 14 compatibility)"

# Build Hyprland (with GCC 14 compatibility patches)
echo "Building Hyprland ${HYPR_VERSION} (10-15 minutes on ARM)..."
echo "  Using: Arch PKGBUILD approach + GCC 14 compatibility patches"
echo "  Patches: #embed → inline string, template deduction, ternary types, C++23 → C++20 APIs"

if ! make release PREFIX=/usr; then
  echo ""
  echo "ERROR: Build failed"
  echo ""
  echo "Possible causes:"
  echo "  - Patches didn't apply correctly (#embed or string concatenation)"
  echo "  - Missing dependencies (check build output above)"
  echo "  - Other GCC 14 vs GCC 15 incompatibilities"
  echo ""
  echo "Fallback: ARM repos have Hyprland 0.49.0 available via:"
  echo "  sudo pacman -S hyprland"
  echo ""
  echo "Note: 0.49.0 config incompatible with x86's 0.51+"

  upload_build_log

  rm -rf "$BUILD_DIR"
  script_exit 1
fi

# Install Hyprland
echo "Installing Hyprland..."
if ! sudo make install PREFIX=/usr; then
  echo "ERROR: Installation failed"
  rm -rf "$BUILD_DIR"
  script_exit 1
fi

# Verify installation
if command -v Hyprland &>/dev/null; then
  NEW_VERSION=$(Hyprland --version 2>&1 | grep -oP 'Hyprland, built from branch .+ at commit .+ \(v\K[0-9.]+' || echo "unknown")
  echo "✓ Hyprland ${NEW_VERSION} installed successfully"
  echo "✓ Using same version/config as x86_64 (${HYPR_VERSION})"
else
  echo "ERROR: Hyprland binary not found after installation"
  rm -rf "$BUILD_DIR"
  script_exit 1
fi

# Cleanup
cd /
rm -rf "$BUILD_DIR"

echo "✓ Hyprland build complete (Arch PKGBUILD + GCC 14 compatibility)"
echo "  Built from release tarball v${HYPR_VERSION}"
echo "  Patched for GCC 14.2.1: #embed, template deduction, ternary types, C++23 APIs"
echo "  Config compatible with Omarchy x86_64"
