BACKGROUNDS_DIR=~/.config/omarchy/backgrounds/

download_background_image() {
  local url="$1"
  local path="$2"
  gum spin --title "Downloading background image..." -- curl -sL -o "$BACKGROUNDS_DIR/$path" "$url"
}

for t in ~/.local/share/omarchy/themes/*; do source "$t/backgrounds.sh"; done
