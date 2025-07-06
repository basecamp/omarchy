# Install Ruby development tools for Fedora
sudo dnf install -y gcc gcc-c++ make

# Note: mise needs to be installed separately on Fedora
# Install mise from GitHub releases or use the install script
if ! command -v mise &>/dev/null; then
  curl https://mise.jdx.dev/install.sh | sh
  echo 'eval "$(~/.local/bin/mise activate bash)"' >>~/.bashrc
  export PATH="$HOME/.local/bin:$PATH"
fi

# Configure mise for Ruby if available
if command -v mise &>/dev/null; then
  mise settings set ruby.ruby_build_opts "CC=gcc CXX=g++"
  # Trust .ruby-version
  mise settings add idiomatic_version_file_enable_tools ruby
fi
