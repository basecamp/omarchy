#!/bin/bash

conf="/etc/vconsole.conf"
hyprconf="$HOME/.config/hypr/hyprland.conf"

layout=$(grep '^XKBLAYOUT=' "$conf" | cut -d= -f2 | tr -d '"')
variant=$(grep '^XKBVARIANT=' "$conf" | cut -d= -f2 | tr -d '"')

if [[ -n "$layout" ]]; then
  sed -i "/^[[:space:]]*kb_options *=/i\  kb_layout = $layout" "$hyprconf"
fi

if [[ -n "$variant" ]]; then
  sed -i "/^[[:space:]]*kb_options *=/i\  kb_variant = $variant" "$hyprconf"
fi
