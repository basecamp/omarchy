#!/usr/bin/env bash
set -e

echo "[omarchy] Migration: add calcurse calendar"

# Install dependency if missing
if ! command -v calcurse >/dev/null 2>&1; then
  echo "[omarchy] Installing calcurse"
  sudo pacman -S --noconfirm calcurse
else
  echo "[omarchy] calcurse already installed"
fi

# Reload Hyprland (ignore if not running)
if command -v hyprctl >/dev/null 2>&1; then
  hyprctl reload || true
fi

# Restart Waybar to pick up new bindings
pkill waybar || true
