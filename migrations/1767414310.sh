echo "Use correct idle-timer sensitive timeouts for screensaver + screen off"

sed -i 's/timeout = 300/timeout = 150/' ~/.config/hypr/hypridle.conf
sed -i 's/timeout = 330/timeout = 30/' ~/.config/hypr/hypridle.conf
