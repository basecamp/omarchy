{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.modules) mkIf;

  cfg = config.omarchy;
in
{
  config = mkIf cfg.enable {
    environment.systemPackages =
      if cfg.qtEnableAdwaita then
        [ pkgs.adwaita-qt ]
      else
        [
          pkgs.libsForQt5.qtstyleplugin-kvantum
          pkgs.qt6Packages.qtstyleplugin-kvantum
        ];
  };
}
