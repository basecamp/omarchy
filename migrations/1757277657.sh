#!/bin/bash

conf="$HOME/.config/hypr/hyprlock.conf"

if ! grep -q "path = \$background" "$conf"; then
  sed -i '/color = \$color/a \    path = \$background' "$conf"
fi
