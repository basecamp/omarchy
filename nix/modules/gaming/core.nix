{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.modules) mkIf;
  inherit (pkgs.stdenv.hostPlatform) isx86_64;

  cfg = config.omarchy;
in
mkIf (cfg.enable && cfg.gaming != null
  && cfg.gaming.steam && isx86_64) {
  programs.steam = {
    enable = true;
    gamescopeSession = {
      enable = true;
      args = [
        "--adaptive-sync"
        "--hdr-enabled"
      ];
    };
    extraCompatPackages = [ pkgs.proton-ge-bin ];
  };

  programs.gamescope = {
    enable = true;
    capSysNice = cfg.gaming.steamRealtime;
    args = lib.optionals cfg.gaming.steamRealtime [ "--rt" ];
  };
}
