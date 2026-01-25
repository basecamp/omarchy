{ pkgs, ... }:
with builtins;
{
  programs.imv.enable = true;

  xdg.configFile."imv/config".source =
    pkgs.replaceVars (path { path = ../../../config/imv/config; })
      {
        inherit (pkgs) imagemagick;
      };
}
