echo "Add hyprsunset blue light filter"
yay -S --noconfirm --needed hyprsunset
cp -r ~/.local/share/omarchy/config/hypr/hyprsunset.conf ~/.config/hypr/
pkill hyprsunset
setsid uwsm app -- hyprsunset &>/dev/null &