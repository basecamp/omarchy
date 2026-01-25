{
  config,
  lib,
  pkgs,
  ...
}:
with builtins;
let
  cfg = config.omarchy;

  themeFile = pkgs.replaceVars (path { path = ../../../default/themed/kitty.conf.tpl; }) {
    inherit (config.omarchy.palette)
      foreground
      background
      selection_foreground
      selection_background
      cursor
      accent
      color0
      color1
      color2
      color3
      color4
      color5
      color6
      color7
      color8
      color9
      color10
      color11
      color12
      color13
      color14
      color15
      ;
  };
in
lib.mkIf (cfg.terminal == "kitty") {
  home.packages = [ pkgs.kitty ];

  xdg.configFile = {
    "kitty/kitty.conf".source = pkgs.replaceVars (path { path = ../../../config/kitty/kitty.conf; }) {
      inherit themeFile;
      font = cfg.font.name;
    };
    "xdg-terminals.list".text = ''
      kitty.desktop
    '';
  };

}
