{
  config,
  lib,
  pkgs,
  omarchyInputs,
  ...
}:
with builtins;
let
  cfg = config.omarchy;
  hyprland = cfg.hyprland.package;

  inherit (lib) getExe getExe';
  inherit (pkgs.stdenv.hostPlatform) system;

  flakes = {
    # walker comes from flake, nixpkgs is too old and doesn't even have elephant
    walker = omarchyInputs.walker.packages.${system}.default;

    # tte is too old in nixpkgs
    tte = omarchyInputs.terminaltexteffects.packages.${system}.default;
  };

  # Executables for script substitution
  exe = {
    # Packages with mainProgram
    awk = getExe pkgs.gawk;
    bc = getExe pkgs.bc;
    bluetui = getExe pkgs.bluetui;
    brotli = getExe pkgs.brotli;
    fastfetch = getExe pkgs.fastfetch;
    fzf = getExe pkgs.fzf;
    gpu-screen-recorder = getExe pkgs.gpu-screen-recorder;
    grep = getExe pkgs.gnugrep;
    grim = getExe pkgs.grim;
    gum = getExe pkgs.gum;
    hypridle = getExe pkgs.hypridle;
    hyprlock = getExe pkgs.hyprlock;
    hyprpicker = getExe pkgs.hyprpicker;
    hyprsunset = getExe pkgs.hyprsunset;
    impala = getExe' pkgs.impala "impala";
    jaq = getExe pkgs.jaq;
    jq = getExe pkgs.jq;
    notify-send = getExe pkgs.libnotify;
    satty = getExe pkgs.satty;
    sed = getExe pkgs.gnused;
    slurp = getExe pkgs.slurp;
    swaybg = getExe pkgs.swaybg;
    tte = getExe flakes.tte;
    walker = getExe flakes.walker;
    waybar = getExe pkgs.waybar;
    wayfreeze = getExe pkgs.wayfreeze;
    wiremix = getExe pkgs.wiremix;
    xdg-terminal-exec = getExe pkgs.xdg-terminal-exec;

    # Packages needing specific binary or getExe'
    bash = "${pkgs.bash}/bin/bash";
    fc-list = "${pkgs.fontconfig}/bin/fc-list";
    ffplay = "${pkgs.ffmpeg}/bin/ffplay";
    find = "${pkgs.findutils}/bin/find";
    hyprctl = getExe' hyprland "hyprctl";
    localsend_app = "${pkgs.localsend}/bin/localsend_app";
    makoctl = "${pkgs.mako}/bin/makoctl";
    pactl = "${pkgs.pulseaudio}/bin/pactl";
    pgrep = "${pkgs.procps}/bin/pgrep";
    pkill = "${pkgs.procps}/bin/pkill";
    powerprofilesctl = "${pkgs.power-profiles-daemon}/bin/powerprofilesctl";
    swayosd-client = "${pkgs.swayosd}/bin/swayosd-client";
    systemctl = "${pkgs.systemd}/bin/systemctl";
    uwsm-app = "${pkgs.uwsm}/bin/uwsm-app";
    v4l2-ctl = "${pkgs.v4l-utils}/bin/v4l2-ctl";
    wl-copy = "${pkgs.wl-clipboard}/bin/wl-copy";
    wl-paste = "${pkgs.wl-clipboard}/bin/wl-paste";
    wpctl = "${pkgs.wireplumber}/bin/wpctl";
    xdg-settings = "${pkgs.xdg-utils}/bin/xdg-settings";
    xargs = "${pkgs.findutils}/bin/xargs";
    xkbcli = "${pkgs.libxkbcommon}/bin/xkbcli";
  };

  createScript =
    name: vars:
    let
      script = pkgs.replaceVars (path { path = ../../../bin/${name}; }) vars;
    in
    pkgs.runCommand name { } ''
      mkdir -p $out/bin
      echo '#!${pkgs.bash}/bin/bash' > $out/bin/${name}
      cat ${script} >> $out/bin/${name}
      chmod +x $out/bin/${name}
    '';

  omarchy-restart-walker = createScript "omarchy-restart-walker" { };

  omarchy-restart-waybar = createScript "omarchy-restart-waybar" {
    inherit (exe) systemctl;
  };

  omarchy-restart-terminal = createScript "omarchy-restart-terminal" {
    inherit (exe) pgrep pkill;
  };

  omarchy-theme-bg-next = createScript "omarchy-theme-bg-next" {
    inherit (exe) find notify-send pkill swaybg uwsm-app;
    inherit (cfg) theme;
    backgroundsDir = path { path = ../../../themes/${cfg.theme}/backgrounds; };
  };

  welcomeDotSh = pkgs.replaceVars (path { path = ../../../install/first-run/welcome.sh; }) {
    inherit (pkgs) libnotify;
  };
  wifiDotSh = pkgs.replaceVars (path { path = ../../../install/first-run/wifi.sh; }) {
    inherit (pkgs) libnotify;
  };

  allScripts = [
    (createScript "omarchy-cmd-audio-switch" {
      inherit (exe)
        grep
        sed
        hyprctl
        jq
        pactl
        swayosd-client
        wpctl
        ;
    })
    (createScript "omarchy-cmd-first-run" {
      inherit (cfg) firstRunMode;
      inherit (exe) bash;
      inherit welcomeDotSh wifiDotSh;
    })
    (createScript "omarchy-cmd-present" { })
    (createScript "omarchy-cmd-reboot" { })
    (createScript "omarchy-cmd-screenrecord" {
      inherit (exe)
        ffplay
        gpu-screen-recorder
        hyprctl
        jq
        notify-send
        v4l2-ctl
        ;
    })
    (createScript "omarchy-cmd-screensaver" {
      inherit (exe)
        hyprctl
        jq
        tte
        ;
      screensaverText = path { path = ../../../logo.txt; };
    })
    (createScript "omarchy-cmd-screenshot" {
      inherit (exe)
        grim
        hyprctl
        jq
        satty
        slurp
        wayfreeze
        wl-copy
        ;
    })
    (createScript "omarchy-cmd-share" {
      inherit (exe)
        fzf
        grep
        localsend_app
        wl-paste
        ;
    })
    (createScript "omarchy-font-current" {
      inherit (exe) grep;
    })
    (createScript "omarchy-font-list" {
      inherit (exe) fc-list grep;
    })
    (createScript "omarchy-font-set" {
      inherit (exe) fc-list grep;
    })
    (createScript "omarchy-cmd-shutdown" { })
    (createScript "omarchy-hyprland-window-close-all" {
      inherit (exe) hyprctl jq xargs;
    })
    (createScript "omarchy-hyprland-window-pop" {
      inherit (exe) hyprctl jq;
    })
    (createScript "omarchy-hyprland-workspace-toggle-gaps" {
      inherit (exe) hyprctl jq;
      gapsOut = if cfg.hyprland.widerWindowGaps then "20" else "10";
      gapsIn = if cfg.hyprland.widerWindowGaps then "10" else "5";
      rounding = if cfg.hyprland.roundWindowCorners then "8" else "0";
    })
    (createScript "omarchy-launch-about" {
      inherit (exe) bash fastfetch;
    })
    (createScript "omarchy-launch-audio" {
      inherit (exe) wiremix;
    })
    (createScript "omarchy-launch-bluetooth" {
      inherit (exe) bluetui;
    })
    (createScript "omarchy-launch-editor" {
      inherit (exe) uwsm-app;
    })
    (createScript "omarchy-launch-floating-terminal-with-presentation" {
      inherit (exe) bash uwsm-app xdg-terminal-exec;
    })
    (createScript "omarchy-launch-or-focus" {
      inherit (exe)
        hyprctl
        jq
        uwsm-app
        ;
    })
    (createScript "omarchy-launch-or-focus-tui" { })
    (createScript "omarchy-launch-or-focus-webapp" { })
    (createScript "omarchy-launch-browser" {
      inherit (exe) uwsm-app xdg-settings;
      webappBrowser = getExe cfg.browser.webapp;
    })
    (createScript "omarchy-launch-screensaver" {
      inherit (exe)
        hyprctl
        jq
        notify-send
        xdg-terminal-exec
        walker
        ;
      alacrittyConf = path { path = ../../../default/alacritty/screensaver.toml; };
      ghosttyConf = path { path = ../../../default/ghostty/screensaver; };
    })
    (createScript "omarchy-launch-tui" {
      inherit (exe) uwsm-app xdg-terminal-exec;
    })
    (createScript "omarchy-launch-walker" {
      inherit (exe) uwsm-app walker;
    })
    (createScript "omarchy-launch-webapp" {
      inherit (exe) xdg-settings uwsm-app;
      webappBrowser = getExe cfg.browser.webapp;
    })
    (createScript "omarchy-launch-wifi" {
      inherit (exe) impala;
    })
    (createScript "omarchy-lock-screen" {
      inherit (exe) hyprctl hyprlock;
    })
    (createScript "omarchy-menu" {
      inherit (exe)
        bash
        hyprpicker
        notify-send
        powerprofilesctl
        xdg-terminal-exec
        walker
        ;
    })
    (createScript "omarchy-menu-keybindings" {
      inherit (exe)
        bc
        awk
        sed
        hyprctl
        jq
        xkbcli
        walker
        ;
    })
    (createScript "omarchy-notification-dismiss" {
      inherit (exe)
        grep
        sed
        makoctl
        ;
    })
    (createScript "omarchy-pkg-install" {
      inherit (exe) awk fzf jq sed;
    })
    (createScript "omarchy-pkg-remove" {
      inherit (exe) fzf jq;
    })
    (createScript "omarchy-powerprofiles-list" {
      inherit (exe) awk powerprofilesctl;
    })
    (createScript "omarchy-restart-app" {
      inherit (exe) uwsm-app;
    })
    (createScript "omarchy-restart-hypridle" { })
    (createScript "omarchy-restart-hyprsunset" { })
    (createScript "omarchy-restart-swayosd" { })
    (createScript "omarchy-restart-walker" { })
    omarchy-restart-terminal
    omarchy-restart-waybar
    (createScript "omarchy-setup-dns" {
      inherit (exe) gum notify-send;
    })
    (createScript "omarchy-show-done" {
      inherit (exe) bash gum;
    })
    (createScript "omarchy-show-logo" {
      logo = path { path = ../../../logo.txt; };
    })
    (createScript "omarchy-state" {
      inherit (exe) find;
    })
    omarchy-theme-bg-next
    (createScript "omarchy-toggle-idle" {
      inherit (exe)
        hypridle
        notify-send
        uwsm-app
        ;
    })
    (createScript "omarchy-toggle-nightlight" {
      inherit (exe)
        grep
        hyprctl
        hyprsunset
        notify-send
        ;
    })
    (createScript "omarchy-toggle-screensaver" {
      inherit (exe) notify-send;
    })
    (createScript "omarchy-toggle-waybar" {
      inherit (exe) systemctl;
    })
    (createScript "omarchy-tz-select" {
      inherit (exe) sed gum;
      CONFIG_FILE = "redo this implementation";
    })
    (createScript "omarchy-update-available" { })
    (createScript "omarchy-update-restart" {
      inherit (exe) gum sed;
    })
  ];
in
{
  options.omarchy.scripts = lib.mkOption {
    type = lib.types.attrs;
    default = { };
    description = "Internal access to omarchy scripts";
  };

  config = {
    omarchy.scripts = {
      inherit omarchy-restart-terminal omarchy-restart-walker omarchy-restart-waybar omarchy-theme-bg-next;
    };
    home.packages = allScripts;

    # Restart apps on activation so they pick up theme changes.
    # Import wayland env vars since activation runs without them.
    home.activation.restartThemedApps = lib.hm.dag.entryAfter [ "onFilesChange" "reloadSystemd" ] ''
      export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
      eval "$(${pkgs.systemd}/bin/systemctl --user show-environment 2>/dev/null | ${pkgs.gnugrep}/bin/grep -E '^(WAYLAND_DISPLAY|HYPRLAND_INSTANCE_SIGNATURE)=')" || true
      export WAYLAND_DISPLAY="''${WAYLAND_DISPLAY:-}" HYPRLAND_INSTANCE_SIGNATURE="''${HYPRLAND_INSTANCE_SIGNATURE:-}"

      ${omarchy-theme-bg-next}/bin/omarchy-theme-bg-next >/dev/null 2>&1 || true
      # uwsm-app doesn't work in activation context; start swaybg in its own scope
      # so it survives the activation service's cgroup cleanup
      sleep 0.2
      if ! ${pkgs.procps}/bin/pgrep -x .swaybg-wrapped >/dev/null 2>&1; then
        ${pkgs.systemd}/bin/systemd-run --user --scope --unit=swaybg-activation \
          ${pkgs.swaybg}/bin/swaybg -i "$HOME/.config/omarchy/current/background" -m fill >/dev/null 2>&1 &
      fi

      ${omarchy-restart-terminal}/bin/omarchy-restart-terminal >/dev/null 2>&1 || true
    '';
  };
}
