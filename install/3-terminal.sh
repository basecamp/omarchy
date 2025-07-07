sudo dnf install -y \
  wget curl unzip net-tools \
  fd-find fzf ripgrep zoxide bat \
  wl-clipboard fastfetch btop \
  man tldr less whois \
  alacritty

# Install eza from GitHub releases (not available in Fedora 42 repos)
if ! command -v eza &>/dev/null; then
  echo "Installing eza from GitHub releases..."
  EZA_VERSION=$(curl -s https://api.github.com/repos/eza-community/eza/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
  wget -O /tmp/eza.tar.gz "https://github.com/eza-community/eza/releases/download/${EZA_VERSION}/eza_x86_64-unknown-linux-gnu.tar.gz"
  sudo tar -xzf /tmp/eza.tar.gz -C /usr/local/bin/ ./eza
  sudo chmod +x /usr/local/bin/eza
  rm /tmp/eza.tar.gz
  echo "eza installed successfully"
fi
