if ! command -v ruby &>/dev/null; then
  # Install Ruby using gcc-14 for compatibility
  paru -S --noconfirm --needed gcc14
  mise settings set ruby.ruby_build_opts "CC=gcc-14 CXX=g++-14"
  mise install ruby
  mise use ruby -g

  # Trust .ruby-version
  mise settings add idiomatic_version_file_enable_tools ruby
fi
