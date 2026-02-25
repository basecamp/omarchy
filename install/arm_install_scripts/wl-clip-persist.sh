#!/bin/bash
#
# Build and install wl-clip-persist from source for ARM
# ARM package page shows v0.5.0 (build date Sept 26, 2025) but mirrors still serve v0.4.3
# v0.4.3 doesn't support negative lookahead regex - we need 0.5.0+ for proper password manager exclusion
# TODO: Remove this once ARM mirrors actually sync v0.5.0
#

set -euo pipefail

VERSION="0.5.0"
REPO_URL="https://github.com/Linus789/wl-clip-persist"
BUILD_DIR="/tmp/wl-clip-persist-build"

echo "Building wl-clip-persist v${VERSION} from source..."

# Check if already installed with correct version
if command -v wl-clip-persist >/dev/null 2>&1; then
    CURRENT_VERSION=$(wl-clip-persist --version | awk '{print $2}')
    if [[ "$CURRENT_VERSION" == "$VERSION" ]]; then
        echo "wl-clip-persist v${VERSION} already installed, skipping build"
        return 0
    fi
fi

# Install build dependencies
echo "Installing build dependencies..."
sudo pacman -S --noconfirm --needed rust cargo

# Clean up any previous build
rm -rf "$BUILD_DIR"

# Clone repository
echo "Cloning wl-clip-persist repository..."
git clone --depth 1 --branch "v${VERSION}" "$REPO_URL" "$BUILD_DIR"
cd "$BUILD_DIR"

# Build
echo "Building wl-clip-persist..."
cargo build --release

# Install binary
echo "Installing wl-clip-persist..."
sudo install -m 755 target/release/wl-clip-persist /usr/local/bin/wl-clip-persist

# Verify installation
INSTALLED_VERSION=$(wl-clip-persist --version | awk '{print $2}')
echo "Successfully installed wl-clip-persist v${INSTALLED_VERSION}"

# Clean up build directory
cd /
rm -rf "$BUILD_DIR"

echo "wl-clip-persist installation complete!"
