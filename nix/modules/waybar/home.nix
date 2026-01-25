{
  config,
  lib,
  pkgs,
  ...
}:
with builtins;
let
  cfg = config.omarchy;

  clockFormat = if cfg.twelveHourClock then "{:L%A %I:%M %p}" else "{:L%A %H:%M}";

  indicatorSource = path { path = ../../../default/waybar/indicators/screen-recording.sh; };
  screen-recording-indicator = pkgs.writeShellScript "screen-recording-wrapped" ''
    exec ${pkgs.bash}/bin/bash ${indicatorSource} "$@"
  '';

  waybarCss = pkgs.replaceVars (path { path = ../../../default/themed/waybar.css.tpl; }) {
    inherit (config.omarchy.palette) foreground background;
  };
in
lib.mkIf cfg.enable {
  programs.waybar = {
    enable = true;
    systemd.enable = true;
  };

  xdg.configFile = {
    "waybar/config.jsonc" = {
      source = pkgs.replaceVars (path { path = ../../../config/waybar/config.jsonc; }) {
        font = cfg.font.name;
        inherit clockFormat screen-recording-indicator;
        inherit (pkgs)
          alacritty
          pamixer
          xdg-terminal-exec
          ;
      };
      onChange = "${cfg.scripts.omarchy-restart-waybar}/bin/omarchy-restart-waybar";
    };
    "waybar/style.css".source = path { path = ../../../config/waybar/style.css; };
    "omarchy/current/theme/waybar.css" = {
      source = waybarCss;
      onChange = "${cfg.scripts.omarchy-restart-waybar}/bin/omarchy-restart-waybar";
    };
  };
}
