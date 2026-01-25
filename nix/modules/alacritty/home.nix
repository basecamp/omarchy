{
  config,
  lib,
  pkgs,
  ...
}:
with builtins;
let
  cfg = config.omarchy;

  themeFile = pkgs.replaceVars (path { path = ../../../default/themed/alacritty.toml.tpl; }) {

    inherit (config.omarchy.palette)
      background
      foreground
      cursor
      selection_foreground
      selection_background
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
lib.mkMerge [
  (lib.mkIf (cfg.terminal == "alacritty") {
    xdg.configFile."xdg-terminals.list".text = ''
      Alacritty.desktop
    '';
  })
  {
    # we're always installing alacritty as an emergency fallback
    home.packages = [ pkgs.alacritty ];

    xdg.configFile = {
      "alacritty/alacritty.toml".source =
        pkgs.replaceVars (path { path = ../../../config/alacritty/alacritty.toml; })
          {
            inherit themeFile;
            font = cfg.font.name;
          };
    };
  }
]
