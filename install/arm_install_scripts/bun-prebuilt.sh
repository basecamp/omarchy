#!/bin/bash

# Bun - JavaScript runtime for ARM
# Installs prebuilt binary to avoid hours-long compilation of JavaScriptCore
# Required as makedepend for: opencode

if command -v bun &>/dev/null; then
  echo "bun already installed, skipping"
  return 0
fi

echo "Installing prebuilt bun for ARM64..."
echo "(Building from source compiles JavaScriptCore which takes hours)"

# Create temporary directory
WORKDIR=$(mktemp -d)
cd "$WORKDIR"

# Download latest ARM64 binary from official releases
echo "Downloading bun-linux-aarch64..."
curl -fsSL "https://github.com/oven-sh/bun/releases/latest/download/bun-linux-aarch64.zip" -o bun.zip

# Extract and install
unzip -q bun.zip
sudo install -Dm755 bun-linux-aarch64/bun /usr/bin/bun

# Cleanup
cd /
rm -rf "$WORKDIR"

# Verify installation
if command -v bun &>/dev/null; then
  echo "bun $(bun --version) installed successfully"
else
  echo "ERROR: bun installation failed"
  return 1
fi
