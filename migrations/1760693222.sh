echo "Use explicit timezone selector when right-clicking on clock"

sed -i 's/omarchy-cmd-tzupdate/omarchy-launch-floating-terminal-with-presentation omarchy-tz-select/g' ~/.config/waybar/config.jsonc
