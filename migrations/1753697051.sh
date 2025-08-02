echo "Adding service to check for Omarchy updates"
if [ ! -f ~/.config/systemd/user/omarchy-check-update.service ]; then
    mkdir -p ~/.config/systemd/user/
    cp ~/.local/share/omarchy/config/systemd/user/omarchy-check-update.* ~/.config/systemd/user/

    systemctl --user daemon-reload
    systemctl --user enable --now omarchy-check-update.timer || true
fi