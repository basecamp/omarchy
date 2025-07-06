sudo dnf install -y \
  cargo clang llvm \
  ImageMagick \
  mariadb-connector-c-devel postgresql-devel \
  gh

# Note: These packages need alternative installation methods on Fedora:
# - mise: install from GitHub releases or use curl -sS https://mise.jdx.dev/install.sh | bash
# - lazygit: available in Fedora repos as 'lazygit'
# - lazydocker-bin: install from GitHub releases

# Install lazygit if available
sudo dnf install -y lazygit || echo "lazygit not available in repos, install from GitHub"
