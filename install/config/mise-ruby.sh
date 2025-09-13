# Install Ruby using gcc-14 for compatibility
mise settings set ruby.ruby_build_opts "CC=gcc-14 CXX=g++-14"

# Trust .ruby-version
mise settings add idiomatic_version_file_enable_tools ruby

# Install pre-built Ruby + Rails for x86_64
if [[ $(uname -m) == "x86_64" ]]; then
  RUBY_VERSION="3.4.5"
  RUBY_TARBALL="ruby-$RUBY_VERSION-rails-8.0.2.1-x86_64.tar.gz"
  RUBY_URL="https://pkgs.omarchy.org/ruby/$RUBY_TARBALL"
  MISE_RUBY_DIR="$HOME/.local/share/mise/installs/ruby"
  OFFLINE_CACHE="/var/cache/omarchy/ruby"

  mkdir -p "$MISE_RUBY_DIR"

  if [[ -n ${OMARCHY_ONLINE_INSTALL:-} ]]; then
    echo "Downloading pre-built Ruby $RUBY_VERSION..."
    curl -fsSL "$RUBY_URL" | tar -xz -C "$MISE_RUBY_DIR"
  else
    echo "Installing Ruby from offline cache..."
    tar -xzf "$OFFLINE_CACHE/$RUBY_TARBALL" -C "$MISE_RUBY_DIR"
  fi

  mise use --global "ruby@${RUBY_VERSION}"
fi
