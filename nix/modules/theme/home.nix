{
  config,
  pkgs,
  lib,
  ...
}:
with builtins;
let
  cfg = config.omarchy;
in
lib.mkIf cfg.enable {
  xdg.configFile = {
    "omarchy/current/theme/obsidian.css".source =
      pkgs.replaceVars
        (path {
          path = ../../../default/themed/obsidian.css.tpl;
        })
        {
          inherit (cfg.palette)
            background
            foreground
            selection_background
            color8
            color1
            color2
            color3
            color4
            color5
            accent
            color6
            ;
        };
    "omarchy/current/theme/chromium.theme".source = pkgs.replaceVars (path {
      path = ../../../default/themed/chromium.theme.tpl;
    }) { inherit (cfg.palette) background_rgb; };
  };
}
