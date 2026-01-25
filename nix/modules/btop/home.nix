{
  config,
  pkgs,
  ...
}:
with builtins;
let
  inherit (pkgs.stdenv.hostPlatform) isx86;
in
{
  programs.btop = {
    enable = true;
    package = pkgs.btop.override {
      rocmSupport = isx86;
      cudaSupport = isx86;
    };
  };

  xdg.configFile."btop/btop.conf".source = path { path = ../../../config/btop/btop.conf; };
  xdg.configFile."btop/themes/current.theme".source =
    pkgs.replaceVars
      (path {
        path = ../../../default/themed/btop.theme.tpl;
      })
      {
        inherit (config.omarchy.palette)
          background
          foreground
          accent
          color1
          color2
          color3
          color4
          color5
          color6
          color8
          ;
      };
}
