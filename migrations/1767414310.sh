echo "Use correct idle-timer sensitive timeouts for lock screen"

sed -i 's/timeout = 300/timeout = 151/' ~/.config/hypr/hypridle.conf
