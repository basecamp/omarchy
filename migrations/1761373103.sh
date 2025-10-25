#!/usr/bin/env bash
set -e

if [[ -f ~/.local/share/omarchy/config/systemd/user/chromium-shutdown.service ]]; then
  cp ~/.local/share/omarchy/config/systemd/user/chromium-shutdown.service ~/.config/systemd/user/chromium-shutdown.service
  systemctl --user enable --now chromium-shutdown.service || true
fi

