o.launch_on_start(o.launch("hypridle"))
o.launch_on_start(o.launch("mako"))
o.launch_on_start("! omarchy-toggle-enabled waybar-off && " .. o.launch("waybar"))
o.launch_on_start(o.launch("fcitx5 --disable notificationitem"))
o.launch_on_start(o.launch("swaybg -i ~/.config/omarchy/current/background -m fill"))
o.launch_on_start("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")
o.launch_on_start("omarchy-first-run")
o.launch_on_start("omarchy-powerprofiles-init")
o.launch_on_start(o.launch("omarchy-hyprland-monitor-watch"))

-- Slow app launch fix -- set systemd vars.
o.launch_on_start("systemctl --user import-environment $(env | cut -d'=' -f 1)")
o.launch_on_start("dbus-update-activation-environment --systemd --all")

-- Run post-boot hooks after startup config has loaded.
o.launch_on_start("sleep 2 && omarchy-hook post-boot")
