{ config, pkgs, ... }:
with builtins;
let
  configTmpl = path { path = ../../../default/themed/mako.ini.tpl; };
in
{
  services.mako = {
    enable = true;
    extraConfig = "include=${
      pkgs.replaceVars configTmpl { inherit (config.omarchy.palette) accent background foreground; }
    }";
  };

  # this is included by the theme file which we're
  # sending in with extraConfig
  xdg.dataFile."omarchy/default/mako/core.ini".source = path {
    path = ../../../default/mako/core.ini;
  };
}
