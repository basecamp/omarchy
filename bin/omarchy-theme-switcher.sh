#!/usr/bin/env bash

echo "╔════════════════════════════════════════╗"
echo "║         OMARCHY THEME INSTALLER        ║"
echo "╚════════════════════════════════════════╝"

for cmd in gum jq curl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: $cmd not found."
    exit 1
  fi
done

omarchy_themes=$(curl -sf https://omarchythemes.com/api/themes/all)

# Build theme list
declare -A THEMES
while IFS= read -r row; do
  name=$(jq -r '.name' <<<"$row" | tr '-' ' ' | sed 's/\b\(.\)/\u\1/g')
  url=$(jq -r '.url' <<<"$row")
  THEMES["$name"]="$url"
done < <(jq -c '.[]' <<<"$omarchy_themes")

SEPARATOR="--------------------------------------------------"

# Theme selection and installation loop
while true; do
  selected=$(printf '%s\n' "${!THEMES[@]}" | sort | gum filter --placeholder="Search themes...")

  if [[ -z "$selected" ]]; then
    echo
    echo "No theme selected."
    break
  fi

  if ! gum confirm "Install theme: $selected?"; then
    echo
    echo "Cancelled."
    continue
  fi

  url="${THEMES[$selected]}"
  echo
  echo "$SEPARATOR"
  echo "🛠️  Installing: $selected"
  echo "$SEPARATOR"
  echo

  if gum spin --spinner dot --title "Installing..." -- omarchy-theme-install "$url"; then
    echo "✅ Installed: $selected"
  else
    echo "❌ Failed to install: $selected"
    echo "$SEPARATOR"
    continue
  fi

  if ! gum confirm "Install another theme?"; then
    echo
    break
  fi
done

echo "$SEPARATOR"
echo "🎉 Theme installation complete."
echo "$SEPARATOR"
