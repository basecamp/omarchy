# This sets up the special keys on Logitech keyboards
if grep -q 'Logitech USB Receiver' /proc/bus/input/devices; then
  echo "Detected Logitech USB Receiver"

  sudo pacman -S --needed --noconfirm solaar

  mkdir -p ~/.config/solaar
  cat <<EOF > ~/.config/solaar/rules.yaml
%YAML 1.3
---
- Key: [Emoji, pressed]
- Execute: [$HOME/.local/share/omarchy/bin/omarchy-launch-walker,-m,symbols]
...
---
- Key: [Screen Capture, pressed]
- Execute: $HOME/.local/share/omarchy/bin/omarchy-cmd-screenshot
...
---
- Key: [Screen Lock, pressed]
- Execute: $HOME/.local/share/omarchy/bin/omarchy-lock-screen
...
EOF

  sudo solaar config "MX Keys S" divert-keys "Emoji" Diverted
  sudo solaar config "MX Keys S" divert-keys "Screen Capture" Diverted
  sudo solaar config "MX Keys S" divert-keys "Screen Lock" Diverted

  cat <<EOF > ~/.config/systemd/user/solaar.service
[Unit]
Description=Solaar
After=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/solaar -w hide -b solaar
Environment=DISPLAY=:0

[Install]
WantedBy=default.target
EOF

  systemctl --user daemon-reload
  systemctl --user enable solaar.service
fi
