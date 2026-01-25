_: {
  services.hyprsunset = {
    enable = true;
    settings = { };
  };

  xdg.configFile."hypr/hyprsunset.conf".source = builtins.path {
    path = ../../../config/hypr/hyprsunset.conf;
  };
}
