echo "Install wf-recorder for screen recording for nvidia"

if [ -n "$(lspci | grep -i 'nvidia')" ] && ! command -v wf-recorder &>/dev/null; then
  yay -S --noconfirm --needed wf-recorder
fi
