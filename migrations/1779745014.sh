echo "Remove old Brave Origin Beta flags file and symlink Brave Origin flags to brave-flags.conf"

mkdir -p ~/.config
rm -f ~/.config/brave-origin-beta-flags.conf ~/.config/brave-origin-flags.conf
ln -s ~/.config/brave-flags.conf ~/.config/brave-origin-flags.conf
