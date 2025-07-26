# do not run if user is using bare mode
if [[ -f ~/.local/state/omarchy/bare.mode ]]; then exit; fi

echo "Add missing installation of Zoom"

if ! command -v zoom &>/dev/null; then
  yay -S --noconfirm --needed zoom
fi
