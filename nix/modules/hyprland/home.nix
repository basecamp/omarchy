{
  config,
  lib,
  omarchyInputs,
  pkgs,
  ...
}:
with builtins;
let
  cfg = config.omarchy;
  inherit (cfg) qtEnableAdwaita;
  hyprCfg = cfg.hyprland;

  inherit (lib) getExe;
  inherit (pkgs.stdenv.hostPlatform) system;

  hyprland-preview-share-picker =
    omarchyInputs.hyprland-preview-share-picker.packages.${system}.default;

  defaults = rec {
    appsDotConf = pkgs.replaceVars (path { path = ../../../default/hypr/apps.conf; }) {
      appsPath = path { path = ../../../default/hypr/apps; };
    };
    autostartDotConf = pkgs.replaceVars (path { path = ../../../default/hypr/autostart.conf; }) {
      inherit (pkgs)
        hypridle
        swaybg
        uwsm
        ;
    };
    bindings = {
      mediaDotConf = pkgs.replaceVars (path { path = ../../../default/hypr/bindings/media.conf; }) {
        inherit (pkgs) jq swayosd;
        hyprland = hyprCfg.package;
      };
      clipboardDotConf = path { path = ../../../default/hypr/bindings/clipboard.conf; };
      tilingV2DotConf = path { path = ../../../default/hypr/bindings/tiling-v2.conf; };
      utilitiesDotConf =
        let
          voxtypePkgs = omarchyInputs.voxtype.packages.${system};
          unwrapped =
            if cfg.voxtype == null then
              null
            else if cfg.voxtype.variant == "vulkan" then
              voxtypePkgs.voxtype-vulkan-unwrapped
            else if cfg.voxtype.variant == "rocm" then
              voxtypePkgs.voxtype-rocm-unwrapped
            else
              voxtypePkgs.voxtype-unwrapped;
          vt =
            if unwrapped == null then
              null
            else
              pkgs.symlinkJoin {
                name = "${unwrapped.pname or "voxtype"}" + "-wrapped-${unwrapped.version}";
                paths = [ unwrapped ];
                buildInputs = [ pkgs.makeWrapper ];
                postBuild = ''
                  wrapProgram $out/bin/voxtype \
                    --prefix PATH : ${
                      lib.makeBinPath [
                        pkgs.wl-clipboard
                        pkgs.libnotify
                        cfg.voxtype.ydotool
                      ]
                    }
                '';
                inherit (unwrapped) meta;
              };
          voxtypeBindings =
            if vt != null then
              ''
                bindd  = SUPER CTRL, X, Start dictation, exec, ${getExe vt} record start
                binddr = SUPER CTRL, X, Stop dictation, exec, ${getExe vt} record stop''
            else
              "";
        in
        pkgs.replaceVars (path { path = ../../../default/hypr/bindings/utilities.conf; }) {
          inherit (pkgs)
            gnome-calculator
            gnugrep
            hyprpicker
            jq
            libnotify
            mako
            ;
          inherit voxtypeBindings;
          hyprland = hyprCfg.package;
        };
    };
    envsDotConf =
      let
        envsLines = concatStringsSep "\n" (attrValues (mapAttrs (k: v: "env = ${k},${v}") hyprCfg.envs));
        envsExtra =
          envsLines + (if envsLines != "" && hyprCfg.envsExtra != "" then "\n" else "") + hyprCfg.envsExtra;
      in
      pkgs.replaceVars (path { path = ../../../default/hypr/envs.conf; }) {
        qtTheme =
          if qtEnableAdwaita then
            (if config.omarchy.lightMode then "adwaita" else "adwaita-dark")
          else
            "kvantum";
        xcompose = path { path = ../../../default/xcompose; };
        inherit envsExtra;
      };
    inputDotConf = pkgs.replaceVars (path { path = ../../../default/hypr/input.conf; }) {
      inherit (cfg.keyboard) layout variant options;
    };
    looknfeelDotConf = path { path = ../../../default/hypr/looknfeel.conf; };
    windowsDotConf = pkgs.replaceVars (path { path = ../../../default/hypr/windows.conf; }) {
      inherit appsDotConf;
    };
  };

  monitorConfig = if hyprCfg.monitorConfig != null then hyprCfg.monitorConfig else "";
  bindingsExtra =
    let
      bindingsLines = concatStringsSep "\n" hyprCfg.bindings;
      extra = if hyprCfg.bindingsExtra != null then hyprCfg.bindingsExtra else "";
    in
    bindingsLines + (if bindingsLines != "" && extra != "" then "\n" else "") + extra;

  configs = {
    inputDotConf = path { path = ../../../config/hypr/input.conf; };
    bindingsDotConf = pkgs.replaceVars (path { path = ../../../config/hypr/bindings.conf; }) {
      inherit (pkgs) nautilus uwsm xdg-terminal-exec;
      inherit (cfg) passwordManager;
      inherit bindingsExtra;
    };
    looknfeelDotConf = pkgs.replaceVars (path { path = ../../../config/hypr/looknfeel.conf; }) {
      inherit (hyprCfg) dwindleExtra;
      rounding = "rounding = ${if hyprCfg.roundWindowCorners then "8" else "0"}";
      gapsSize =
        if !hyprCfg.widerWindowGaps then
          ""
        else
          ''
            gaps_in = 10
            gaps_out = 20
          '';
    };
    monitorsDotConf = pkgs.replaceVars (path { path = ../../../config/hypr/monitors.conf; }) {
      inherit monitorConfig;
    };
    autostartDotConf = path { path = ../../../config/hypr/autostart.conf; };
  };

  lockSecs = 60 * cfg.screensaver.lockMinutes;
  screensaver = {
    activationSeconds = toString (60 * cfg.screensaver.activationMinutes);
    lockSeconds = toString lockSecs;
    screenOffDelaySeconds = toString (cfg.screensaver.screenOffDelaySeconds + lockSecs);
  };
in
{
  services.polkit-gnome.enable = true;

  xdg.configFile = {
    "hypr/hyprland.conf".source =
      pkgs.replaceVars (path { path = ../../../config/hypr/hyprland.conf; })
        {
          defaultAutostartDotConf = defaults.autostartDotConf;
          defaultBindingsMediaDotConf = defaults.bindings.mediaDotConf;
          defaultBindingsClipboardDotConf = defaults.bindings.clipboardDotConf;
          defaultBindingsTilingV2DotConf = defaults.bindings.tilingV2DotConf;
          defaultBindingsUtilitiesDotConf = defaults.bindings.utilitiesDotConf;
          defaultEnvsDotConf = defaults.envsDotConf;
          defaultLooknfeelDotConf = defaults.looknfeelDotConf;
          defaultInputDotConf = defaults.inputDotConf;
          defaultWindowsDotConf = defaults.windowsDotConf;
          themeFile = pkgs.replaceVars (path { path = ../../../default/themed/hyprland.conf.tpl; }) {
            inherit (config.omarchy.palette) accent_strip;
          };

          configMonitorsDotConf = configs.monitorsDotConf;
          configInputDotConf = configs.inputDotConf;
          configBindingsDotConf = configs.bindingsDotConf;
          configLooknfeelDotConf = configs.looknfeelDotConf;
          configAutostartDotConf = configs.autostartDotConf;
        };

    "hypr/hypridle.conf".source =
      pkgs.replaceVars (path { path = ../../../config/hypr/hypridle.conf; })
        {
          inherit (pkgs) brightnessctl;
          hyprland = hyprCfg.package;
          inherit (screensaver) activationSeconds lockSeconds screenOffDelaySeconds;
        };

    "hypr/xdph.conf".source = pkgs.replaceVars (path { path = ../../../config/hypr/xdph.conf; }) {
      inherit hyprland-preview-share-picker;
    };
  };
}
