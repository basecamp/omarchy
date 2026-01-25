_: with builtins; {
  programs.fastfetch = {
    enable = true;
  };

  xdg.configFile."fastfetch/config.jsonc".source = path {
    path = ../../../config/fastfetch/config.jsonc;
  };
}
