{ config, pkgs, ... }:
with builtins;
let
  cfg = config.omarchy;

  themeCss = pkgs.replaceVars (path { path = ../../../default/themed/swayosd.css.tpl; }) {
    inherit (config.omarchy.palette) background foreground accent;
  };
in
{
  services.swayosd.enable = true;

  xdg.configFile."swayosd/config.toml".source = path { path = ../../../config/swayosd/config.toml; };
  xdg.configFile."swayosd/style.css".source =
    pkgs.replaceVars (path { path = ../../../config/swayosd/style.css; })
      {
        inherit themeCss;
        font = cfg.font.name;
      };
}
