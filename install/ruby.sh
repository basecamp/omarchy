# Install Ruby using gcc-14 for compatibility
if ! command -v ruby &>/dev/null; then
  yay -S --noconfirm --needed gcc14
  mise set -g CC=gcc-14 CXX=g++-14
  mise install -g ruby
fi
