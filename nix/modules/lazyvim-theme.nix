{
  config,
  ...
}:
with builtins;
let
  cfg = config.omarchy;

  themeFile = path {
    path = ../../themes/${cfg.theme}/neovim.lua;
  };
in
readFile themeFile
