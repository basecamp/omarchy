# Setup sudo-less controls for controlling brightness on Apple Displays.
# asdcontrol is only relevant if the package is installed.
if omarchy-cmd-present asdcontrol; then
  echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/asdcontrol" | sudo tee /etc/sudoers.d/asdcontrol
  sudo chmod 440 /etc/sudoers.d/asdcontrol
else
  echo "asdcontrol not installed — skipping sudoless setup"
fi
