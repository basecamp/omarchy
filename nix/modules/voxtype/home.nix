{
  config,
  lib,
  pkgs,
  omarchyInputs,
  ...
}:
with builtins;
let
  inherit (lib.modules) mkIf;
  inherit (lib) getExe;
  inherit (pkgs.stdenv.hostPlatform) system;

  cfg = config.omarchy;
  vt = cfg.voxtype;

  voxtypePkgs = omarchyInputs.voxtype.packages.${system};

  unwrapped =
    if vt.variant == "vulkan" then
      voxtypePkgs.voxtype-vulkan-unwrapped
    else if vt.variant == "rocm" then
      voxtypePkgs.voxtype-rocm-unwrapped
    else
      voxtypePkgs.voxtype-unwrapped;

  runtimeDeps = [
    pkgs.wl-clipboard
    pkgs.libnotify
    vt.ydotool
  ];

  package = pkgs.symlinkJoin {
    name = "${unwrapped.pname or "voxtype"}-wrapped-"
      + "${unwrapped.version}";
    paths = [ unwrapped ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/voxtype \
        --prefix PATH : ${lib.makeBinPath runtimeDeps}
    '';
    inherit (unwrapped) meta;
  };

  feedback = vt.audioFeedback;

  models = import "${omarchyInputs.voxtype}/nix/models.nix";

  whisperModel = pkgs.fetchurl {
    inherit (models.${vt.model}) url hash;
  };
in
mkIf (vt != null) {
  home.packages = [ package ];

  systemd.user.services.voxtype = {
    Unit = {
      Description = "VoxType voice-to-text daemon";
      PartOf = [ "graphical-session.target" ];
      After = [
        "graphical-session.target"
        "pipewire.service"
        "pipewire-pulse.service"
      ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${getExe package} daemon";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  xdg.configFile."voxtype/config.toml".source =
    pkgs.replaceVars
      (path { path = ../../../default/voxtype/config.toml; })
      {
        inherit whisperModel;
        audioFeedbackEnabled =
          if feedback != null then "true" else "false";
        audioFeedbackTheme =
          if feedback != null then feedback.theme
          else "default";
        audioFeedbackVolume =
          toString (if feedback != null then feedback.volume
          else 0.7);
      };
}
