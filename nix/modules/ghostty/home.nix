{
  config,
  lib,
  pkgs,
  ...
}:
with builtins;
let
  cfg = config.omarchy;
  themeFile = pkgs.replaceVars (path { path = ../../../default/themed/ghostty.conf.tpl; }) {
    inherit (config.omarchy.palette)
      background
      foreground
      cursor
      selection_background
      selection_foreground
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

  warpShader = pkgs.fetchurl {
    url = "https://github.com/sahaj-b/ghostty-cursor-shaders/raw/88c27a55b2e970eec19c21ef858a1a5bea489a1d/cursor_warp.glsl";
    sha256 = "sha256-9ZlLcNu5cH0Ibc7qrS+lfrY4neesQm/5FdTCNa85G+s=";
  };
in
lib.mkIf (cfg.terminal == "ghostty") {
  programs.ghostty.enable = true;

  xdg.configFile = {
    "ghostty/config".source = pkgs.replaceVars (path { path = ../../../config/ghostty/config; }) {
      inherit themeFile;
      font = cfg.font.name;
      shaderFile = warpShader;
      # always animate cursor shader since otherwise it can get
      # stuck when switching windows. a full-terminal crazy shader
      # probably should be set to `true` instead so it only animates
      # when the terminal is focused.
      customShaderAnimation = "always";
    };
    "xdg-terminals.list".text = ''
      com.mitchellh.ghostty.desktop
    '';
  };
}
