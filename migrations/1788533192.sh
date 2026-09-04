echo "Install a local speech backend so Web Speech works in Brave and other browsers"

omarchy-pkg-add speech-dispatcher espeak-ng

systemctl --user daemon-reload >/dev/null 2>&1 || true

# speech-dispatcher.socket is a distro unit (WantedBy=sockets.target). Enable
# without assuming a live user manager: an update from a TTY still needs the
# symlink so the next graphical login has voices. --now starts it immediately
# when the user manager is up, so an already-open session does not wait.
if ! systemctl --user enable --now speech-dispatcher.socket >/dev/null 2>&1; then
  wants_dir="$HOME/.config/systemd/user/sockets.target.wants"
  mkdir -p "$wants_dir"
  ln -sfn /usr/lib/systemd/user/speech-dispatcher.socket \
    "$wants_dir/speech-dispatcher.socket"
fi
