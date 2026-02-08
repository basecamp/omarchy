# Ensure fish is the default shell (CachyOS default, may be overridden during install)
if command -v fish &>/dev/null && [ "$(getent passwd $USER | cut -d: -f7)" != "/usr/bin/fish" ]; then
  sudo chsh -s /usr/bin/fish $USER
fi
