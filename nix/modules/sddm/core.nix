{
  config,
  lib,
  ...
}:
let
  inherit (lib.modules) mkIf;

  cfg = config.omarchy;
in
mkIf cfg.enable {
  services.displayManager = {
    autoLogin = {
      enable = true;
      user = cfg.username;
    };
    defaultSession = "hyprland-uwsm";
    sddm = {
      enable = true;
      theme = "breeze";
      wayland.enable = true;
      autoLogin.relogin = true;
    };
  };

  programs.uwsm.waylandCompositors.hyprland.binPath =
    lib.mkForce "${cfg.hyprland.package}/bin/start-hyprland";
}
