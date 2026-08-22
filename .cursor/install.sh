#!/bin/bash

# Cloud Agent bootstrap for the Omarchy repository.
#
# Omarchy targets Arch Linux, where the shell/CLI/theme tooling assumes GNU
# userland tools (gawk, coreutils), Lua 5.4, ImageMagick 7 (`magick`), and a
# handful of runtime helpers. Cloud Agents boot Ubuntu, so this script installs
# the Arch-parity toolchain the non-graphical test suites (`./test/all`) need
# and exposes the repo's `bin/` on PATH the way a real Omarchy session does.
#
# It is idempotent: it may run repeatedly against cached state.

set -euo pipefail

OMARCHY_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq

# System packages the test suites and CLI rely on:
# - gawk: `\s` regex and strtonum() used by theme/power/bar helpers (mawk lacks both)
# - lua5.4: Hyprland config unit tests (ships /usr/bin/lua via alternatives)
# - imagemagick: wallpaper sampling in omarchy-bar-text-color (magick shim below)
# - python-is-python3: a few tests invoke bare `python`
# - iproute2: `ip route` interface detection in omarchy-network-qr
# - qrencode: Wi-Fi QR generation
# - jq / ripgrep / git / curl: pervasive across CLI and shell tests
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
  gawk \
  lua5.4 \
  imagemagick \
  python3 \
  python-is-python3 \
  iproute2 \
  qrencode \
  jq \
  ripgrep \
  git \
  curl \
  ca-certificates

# Omarchy calls ImageMagick 7's unified `magick` binary. Ubuntu ships
# ImageMagick 6, which only installs `convert`. The operations Omarchy uses
# (geometry, cropping, -format '%[fx:...]' info:-) are identical in v6, so a
# thin shim keeps `magick ...` working. Never clobber a real v7 install.
if ! command -v magick >/dev/null && command -v convert >/dev/null; then
  printf '#!/bin/bash\nexec /usr/bin/convert "$@"\n' | sudo tee /usr/local/bin/magick >/dev/null
  sudo chmod +x /usr/local/bin/magick
fi

# On a real Omarchy system the uwsm session exports OMARCHY_PATH and puts the
# command set on PATH. Reproduce that for every shell so the CLI and tests that
# expect ambient `omarchy-*` commands (e.g. omarchy-hw-hybrid-gpu) resolve.
profile_script="/etc/profile.d/omarchy-dev.sh"
sudo tee "$profile_script" >/dev/null <<EOF
# Added by Omarchy Cloud Agent setup (.cursor/install.sh)
export OMARCHY_PATH="$OMARCHY_PATH"
case ":\$PATH:" in
  *":$OMARCHY_PATH/bin:"*) ;;
  *) export PATH="$OMARCHY_PATH/bin:\$PATH" ;;
esac
EOF
sudo chmod +x "$profile_script"

# Non-login interactive shells (and the agent's shells) read ~/.bashrc rather
# than /etc/profile.d, so source the same block there too. Guard against
# duplicate appends to stay idempotent.
bashrc="$HOME/.bashrc"
marker="# >>> omarchy dev env >>>"
if ! grep -qF "$marker" "$bashrc" 2>/dev/null; then
  {
    printf '\n%s\n' "$marker"
    printf '[ -f %s ] && source %s\n' "$profile_script" "$profile_script"
    printf '# <<< omarchy dev env <<<\n'
  } >>"$bashrc"
fi

echo "Omarchy Cloud Agent environment ready. OMARCHY_PATH=$OMARCHY_PATH"
