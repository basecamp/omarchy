# Install Python packages for biology
# Uses uv (via Omarchy's Python dev environment)

# Check if uv is installed, if not, install Python dev environment first
if ! command -v uv &> /dev/null; then
  echo "Python dev environment not found. Installing via Omarchy..."
  omarchy-install-dev-env python

  # Source shell config to get uv in PATH
  if [ -f "$HOME/.bashrc" ]; then
    source "$HOME/.bashrc"
  fi
fi

# Install packages using uv
mapfile -t packages < <(grep -v '^#' "$OMARCHY_INSTALL/python-bio.txt" | grep -v '^$')

if [ ${#packages[@]} -gt 0 ]; then
  echo "Installing Python biology packages with uv..."
  for package in "${packages[@]}"; do
    echo "Installing: $package"
    uv pip install --system "$package" || echo "Warning: Failed to install $package"
  done
  echo "Python biology packages installed"
else
  echo "No Python packages to install"
fi
