echo "Installing 1Password for ARM..."

# Check if 1Password is already installed
if command -v 1password &>/dev/null; then
  echo "1Password already installed, skipping"
  return 0
fi

curl -sSO https://downloads.1password.com/linux/tar/stable/aarch64/1password-latest.tar.gz
tar -xf 1password-latest.tar.gz
sudo mkdir -p /opt/1Password && sudo mv 1password-*/* /opt/1Password
sudo /opt/1Password/after-install.sh

# Clean up downloaded files
rm -f 1password-latest.tar.gz
rm -rf 1password-*/

cd ~

echo "1Password installed successfully"

