# Temporary until upstream/Arch btop includes Intel xe GPU support.

if omarchy-hw-intel-xe && pacman -Si btop-xe &>/dev/null; then
  yes | sudo pacman -S --needed btop-xe
fi
