if ! command -v 1password &>/dev/null; then
  cd /tmp
  curl -sSO https://downloads.1password.com/linux/tar/edge/x86_64/1password-latest.tar.gz
  tar -xf 1password-latest.tar.gz
  sudo mkdir -p /opt/1Password
  sudo mv 1password-*/* /opt/1Password
  sudo /opt/1Password/after-install.sh
  rm -rf 1password*
  cd -

  yay -S --noconfirm --needed 1password-cli
fi
