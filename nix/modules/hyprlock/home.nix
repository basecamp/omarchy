{ config, pkgs, ... }:
with builtins;
let
  cfg = config.omarchy;

  themeFile = pkgs.replaceVars (path { path = ../../../default/themed/hyprlock.conf.tpl; }) {
    inherit (config.omarchy.palette) background_rgb foreground_rgb accent_rgb;
  };
in
{
  programs.hyprlock = {
    enable = true;
    settings = { };
  };

  xdg.configFile."hypr/hyprlock.conf".source =
    pkgs.replaceVars (path { path = ../../../config/hypr/hyprlock.conf; })
      {
        inherit themeFile;
        font = cfg.font.name;
      };
}
