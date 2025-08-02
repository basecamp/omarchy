echo "Add hyprsunset blue light filter"
if ! command -v hyprsunset &>/dev/null; then
    yay -S --noconfirm --needed hyprsunset
fi
cp -r ~/.local/share/omarchy/config/hypr/hyprsunset.conf ~/.config/hypr/
pkill hyprsunset
setsid uwsm app -- hyprsunset &>/dev/null &