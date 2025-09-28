#!/usr/bin/env bash

set -e

GREEN='\e[92m'
NC='\e[0m'

if ! command -v gum &>/dev/null; then
  echo "Error: gum not found. Install with: pacman -S gum"
  exit 1
fi

mapfile -t theme_urls < <(
  curl -s https://github.com/aorumbayev/awesome-omarchy |
    grep -oP 'https://github.com/[a-zA-Z0-9._-]+/omarchy-[a-zA-Z0-9._-]+-theme'
)

declare -A THEMES
for url in "${theme_urls[@]}"; do
  name=$(echo "$url" | sed -E 's#.*/omarchy-([a-zA-Z0-9._-]+)-theme#\1#' | tr '-' ' ' | sed 's/\b\(.\)/\u\1/g')
  THEMES["$name"]="$url"
done

while true; do
  echo "╔════════════════════════════════════════╗"
  echo "║         OMARCHY THEME INSTALLER        ║"
  echo "╚════════════════════════════════════════╝"

  selected=$(printf '%s\n' "${!THEMES[@]}" | sort | gum filter --placeholder="Search themes...")

  if [ -z "$selected" ]; then
    echo "No theme selected."
    break
  fi

  echo
  if ! gum confirm "Install theme: $selected?"; then
    echo "Cancelled."
    continue
  fi

  url="${THEMES[$selected]}"
  echo "Installing: $selected"
  echo
  echo *─────────────────────***─────────────────────*
  echo

  if gum spin --spinner dot --title "Installing..." -- omarchy-theme-install "$url"; then
    echo -e "${GREEN}✓ Installed '$selected'${NC}"
    echo
    echo "Select it: Super + Ctrl + Shift + Space"
  else
    echo "✗ Failed to install '$selected'"
    continue
  fi

  echo
  echo *─────────────────────***─────────────────────*
  echo

  if ! gum confirm "Install another theme?"; then
    break
  fi
done

echo -e "${GREEN}Theme installation complete.${NC}"
echo
echo *─────────────────────***─────────────────────*
