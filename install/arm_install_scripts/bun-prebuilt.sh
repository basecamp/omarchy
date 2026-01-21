#!/bin/bash

# Bun - JavaScript runtime for ARM
# Installs prebuilt binary as a proper pacman package to satisfy dependency checks
# Required as makedepend for: opencode
# Building from source compiles JavaScriptCore (3400+ files) which takes hours

# Check if bun is already registered with pacman
if pacman -T bun &>/dev/null; then
  echo "bun already satisfied, skipping"
  return 0
fi

echo "Installing prebuilt bun for ARM64..."
echo "(Building from source compiles JavaScriptCore which takes hours)"

# Create temporary directory
WORKDIR=$(mktemp -d)
cd "$WORKDIR"

# Get latest version from GitHub API
echo "Fetching latest bun version..."
BUN_VERSION=$(curl -fsSL "https://api.github.com/repos/oven-sh/bun/releases/latest" | grep -oP '"tag_name": "bun-v\K[^"]+' | head -1)
if [ -z "$BUN_VERSION" ]; then
  echo "Failed to get version, using fallback..."
  BUN_VERSION="1.2.5"
fi
echo "Installing bun version: $BUN_VERSION"

# Download ARM64 binary from official releases
echo "Downloading bun-linux-aarch64..."
curl -fsSL "https://github.com/oven-sh/bun/releases/latest/download/bun-linux-aarch64.zip" -o bun.zip
unzip -q bun.zip

# Create PKGBUILD to register with pacman (satisfies dependency checks)
cat > PKGBUILD << EOF
pkgname=bun-prebuilt
pkgver=${BUN_VERSION}
pkgrel=1
pkgdesc='Incredibly fast JavaScript runtime (prebuilt ARM64 binary)'
arch=('aarch64')
url='https://bun.sh'
license=('MIT')
provides=('bun')
conflicts=('bun' 'bun-git')

package() {
  install -Dm755 "\$srcdir/../bun-linux-aarch64/bun" "\$pkgdir/usr/bin/bun"
}
EOF

# Build and install the package
echo "Building pacman package..."
makepkg -si --noconfirm --skipchecksums --skipinteg 2>/dev/null

# Cleanup
cd /
rm -rf "$WORKDIR"

# Verify installation
if pacman -T bun &>/dev/null; then
  echo "bun $(bun --version) installed successfully (registered with pacman)"
else
  echo "ERROR: bun installation failed"
  return 1
fi
