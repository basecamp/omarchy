echo "Move calendar to SUPER + SHIFT + C"
sed -i 's/bindd = SUPER, C, Calendar, exec, omarchy-launch-webapp "https:\/\/app\.hey\.com\/calendar\/weeks\/"/bindd = SUPER SHIFT, C, Calendar, exec, omarchy-launch-webapp "https:\/\/app.hey.com\/calendar\/weeks\/"/' ~/.config/hypr/*.conf
