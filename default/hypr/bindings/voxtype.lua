-- Want push-to-talk on a bare modifier key (e.g. Right Cmd/Super) instead of
-- F9? Hyprland can't fire a release-bind for a lone modifier key
-- (https://github.com/hyprwm/Hyprland/issues/6946), so o.bind can't do this.
-- Use voxtype's own built-in evdev hotkey instead:
-- ~/.config/voxtype/config.toml -> [hotkey] enabled = true, key = "RIGHTMETA"
if o.cmd_present("voxtype") then
  o.bind("SUPER + CTRL + X", "Toggle dictation", "voxtype record toggle")
  o.bind("F9", "Start dictation (push-to-talk)", "voxtype record start")
  o.bind("F9", "Stop dictation (push-to-talk)", "voxtype record stop", { release = true })
end
