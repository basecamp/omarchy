#!/usr/bin/env bash

set -euo pipefail

# 1Password CLI Installer for ARM
# Installs v2.32.0 - use 'op update' to update to newer versions

readonly OP_VERSION="v2.32.0"
readonly INSTALL_PATH="/usr/local/bin/op"

# Skip if already installed
if command -v op &> /dev/null; then
  return 0
fi

# Detect architecture
arch=$(uname -m)
case "$arch" in
    aarch64|arm64) arch="arm64" ;;
    armv7l|armv6l) arch="arm" ;;
    *) echo "Unsupported architecture: $arch" >&2; exit 1 ;;
esac

# Download and extract
temp_dir=$(mktemp -d)
trap "rm -rf $temp_dir" EXIT

curl -fsSL "https://cache.agilebits.com/dist/1P/op2/pkg/${OP_VERSION}/op_linux_${arch}_${OP_VERSION}.zip" -o "${temp_dir}/op.zip"
mkdir -p "${temp_dir}/op"
bsdtar -xf "${temp_dir}/op.zip" -C "${temp_dir}/op"

# Install
sudo mv "${temp_dir}/op/op" "$INSTALL_PATH"

# Set up permissions
getent group onepassword-cli &> /dev/null || sudo groupadd onepassword-cli
sudo chgrp onepassword-cli "$INSTALL_PATH"
sudo chmod g+s "$INSTALL_PATH"
