{
  config,
  lib,
  osConfig ? { },
  pkgs,
  ...
}:
let
  inherit (lib.modules) mkIf;

  cfg = config.omarchy;
  gaming = osConfig.omarchy.gaming or null;
in
mkIf (cfg.enable && gaming != null
  && gaming.heroicGameLauncher) {
  home.packages = [ pkgs.heroic ];
}
