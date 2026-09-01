echo "Keep desktop shortcuts out of the home directory"

user_dirs="$HOME/.config/user-dirs.dirs"
desktop_dir="$HOME/.local/share/desktop"

[[ -f $user_dirs ]] || exit 0

unset XDG_DESKTOP_DIR
source "$user_dirs"

[[ ${XDG_DESKTOP_DIR:-} == $HOME ]] || exit 0

mkdir -p "$desktop_dir"
xdg-user-dirs-update --set DESKTOP "$desktop_dir"
