echo "Add new matte black theme"

BACKGROUNDS_DIR=~/.config/omarchy/backgrounds/
download_background_image() {
  local url="$1"
  local path="$2"
  gum spin --title "Downloading $url as $path..." -- curl -sL -o "$BACKGROUNDS_DIR/$path" "$url"
}

if [[ ! -L "~/.config/omarchy/themes/matte-black" ]]; then
  ln -snf ~/.local/share/omarchy/themes/matte-black ~/.config/omarchy/themes/
  source ~/.local/share/omarchy/themes/matte-black/backgrounds.sh
fi
