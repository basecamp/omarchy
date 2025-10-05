echo "Correct path for sudoless asdcontrol for working Apple Display hotkeys"

if [[ $(command -v asdcontrol) == "/usr/bin/asdcontrol" ]]; then
  echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/asdcontrol" | sudo tee /etc/sudoers.d/asdcontrol
fi
