{
  config,
  omarchyInputs,
  pkgs,
  ...
}:
with builtins;
let
  inherit (pkgs.stdenv.hostPlatform) system;

  themeFile =
    pkgs.replaceVars (path { path = ../../../default/themed/hyprland-preview-share-picker.css.tpl; })
      {
        inherit (config.omarchy.palette)
          foreground
          background
          accent
          color8
          color0
          color12
          ;
      };
in
{
  home.packages = [
    omarchyInputs.hyprland-preview-share-picker.packages.${system}.default
  ];

  xdg.configFile."hyprland-preview-share-picker/config.yaml".source =
    pkgs.replaceVars (path { path = ../../../config/hyprland-preview-share-picker/config.yaml; })
      {
        inherit (pkgs) slurp;
        inherit themeFile;
      };
}
