echo "Installing 'glow' for displaying markdown content in the terminal - For new omarchy-release-notes"

if ! pacman -Q glow &>/dev/null; then
    sudo pacman -S --noconfirm glow
fi