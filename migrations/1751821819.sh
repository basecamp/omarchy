echo "Install bash-completion"

if ! pacman -Q bash-completion &>/dev/null; then
  sudo pacman -S --noconfirm --needed bash-completion
fi
