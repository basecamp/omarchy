echo "Install bash-completion"

if ! pacman -Q bash-completion &>/dev/null; then
  yay -S --noconfirm --needed bash-completion
fi
