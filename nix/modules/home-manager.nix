{
  self,
  inputs,
}:
{
  config,
  lib,
  osConfig ? { },
  pkgs,
  ...
}:
with builtins;
let
  inherit (lib)
    splitString
    findFirst
    hasPrefix
    toInt
    last
    ;
  inherit (lib.modules) mkDefault mkIf;

  cfg = config.omarchy;

  envFile = path { path = ../../default/hypr/envs.conf; };

  cursorSize =
    let
      lines = splitString "\n" (readFile envFile);
      line = findFirst (l: hasPrefix "env = XCURSOR_SIZE," l) null lines;
    in
    if line != null then
      toInt (last (splitString "," line))
    else
      throw "Failed to extract XCURSOR_SIZE from ${envFile}. The file format may have changed and the parsing logic in nix/modules/home-manager.nix needs to be updated.";
in
{
  imports = [
    inputs.walker.homeManagerModules.default
    ./alacritty/home.nix
    ./btop/home.nix
    ./fastfetch/home.nix
    ./gaming/home.nix
    ./ghostty/home.nix
    ./gtk/home.nix
    ./hyprland/home.nix
    ./hyprland-preview-share-picker/home.nix
    ./hyprlock/home.nix
    ./hyprsunset/home.nix
    ./imv/home.nix
    ./kitty/home.nix
    ./mako/home.nix
    ./mpv/home.nix
    ./options/home.nix
    ./scripts/home.nix
    ./swayosd/home.nix
    ./theme/home.nix
    ./voxtype/home.nix
    ./walker/home.nix
    ./waybar/home.nix
    ./xdg/home.nix
  ];

  config = mkIf cfg.enable {
    _module.args.omarchyInputs = inputs;
    _module.args.self = self;

    omarchy.qtEnableAdwaita = mkDefault (osConfig.omarchy.qtEnableAdwaita or false);

    home.packages = with pkgs; [
      cfg.font.package
      liberation_ttf
    ];

    xdg.configFile."fontconfig/conf.d/50-omarchy.conf".source = pkgs.replaceVars (path {
      path = ../../config/fontconfig/fonts.conf;
    }) { font = config.omarchy.font.name; };

    home.pointerCursor = {
      gtk.enable = true;
      x11.enable = true;
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
      size = cursorSize;
    };
  };
}
