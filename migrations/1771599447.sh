echo "Delay after sleep for PAM readiness before turning on display"

sed -i 's/after_sleep_cmd = hyprctl dispatch dpms on/after_sleep_cmd = sleep 1 \&\& hyprctl dispatch dpms on/' ~/.config/hypr/hypridle.conf
