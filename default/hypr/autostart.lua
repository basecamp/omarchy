hl.on("hyprland.start", function()
  -- Slow app launch fix -- set systemd vars before starting session services.
  hl.exec_cmd("systemctl --user import-environment $(env | cut -d'=' -f 1)")
  hl.exec_cmd("dbus-update-activation-environment --systemd --all")

  hl.exec_cmd("quickshell -n -p $HOME/.local/share/omarchy/shell")
  hl.exec_cmd("uwsm-app -- fcitx5 --disable notificationitem")
  hl.exec_cmd("omarchy-first-run")
  hl.exec_cmd("omarchy-powerprofiles-init")
  hl.exec_cmd("uwsm-app -- omarchy-hyprland-monitor-watch")

  -- Run post-boot hooks after startup config has loaded.
  hl.exec_cmd("sleep 2 && omarchy-hook post-boot")
end)
