echo "Remove old Brave Origin Beta flags file and symlink Brave Origin flags to brave-flags.conf"

rm -f ~/.config/brave-origin-beta-flags.conf

if [[ ! -e ~/.config/brave-origin-flags.conf ]]; then
  ln -s brave-flags.conf ~/.config/brave-origin-flags.conf
fi
