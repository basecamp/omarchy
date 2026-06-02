echo "Symlink Brave Origin flags to brave-flags.conf so both browsers share configuration"

if [[ ! -e ~/.config/brave-origin-flags.conf ]]; then
  ln -s brave-flags.conf ~/.config/brave-origin-flags.conf
fi
