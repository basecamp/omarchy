echo "Symlink Brave Origin Beta flags to brave-flags.conf so both browsers share configuration"

if [[ ! -e ~/.config/brave-origin-beta-flags.conf ]]; then
  ln -s brave-flags.conf ~/.config/brave-origin-beta-flags.conf
fi
