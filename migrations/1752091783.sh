echo "Install Plymouth splash screen"
if ! command -v plymouth &>/dev/null; then
  yay -S --noconfirm --needed plymouth
  bash "$HOME/.local/share/omarchy/install/plymouth.sh"
fi
