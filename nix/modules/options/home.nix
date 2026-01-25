{
  config,
  lib,
  pkgs,
  self,
  ...
}:
with builtins;
let
  inherit (lib.modules) mkIf mkMerge;
  inherit (lib.options) mkOption mkEnableOption mkPackageOption;
  inherit (lib.meta) getExe;
  inherit (lib.types)
    attrsOf
    bool
    enum
    float
    int
    lines
    listOf
    nullOr
    oneOf
    str
    submodule
    ;
  inherit (lib)
    concatMapAttrs
    hasPrefix
    importTOML
    literalExpression
    mapAttrs'
    mapAttrsToList
    mkDefault
    nameValuePair
    optional
    removePrefix
    stringToCharacters
    toUpper
    types
    ;

in
{
  options = {
    omarchy = {
      enable = mkEnableOption self.description;

      qtEnableAdwaita = mkEnableOption "Adwaita theme for Qt applications";

      browser = mkOption {
        type = nullOr (submodule {
          options = {
            webapp = mkPackageOption pkgs "brave" {
              default = "brave";
              example = "microsoft-edge";
              extraDescription = "The chromium-based web browser to use for launching webapps. It will also be used as a fallback if no default browser can be found.";
            };
          };
        });
      };

      firstRunMode = mkOption {
        type = bool;
        default = true;
        description = "Show the introductory notifications.";
      };

      font = mkOption {
        type = nullOr (submodule {
          options = {
            package = mkPackageOption pkgs.nerd-fonts "font" {
              default = "jetbrains-mono";
              example = "fira-code";
              pkgsText = "pkgs.nerd-fonts";
            };
            name = mkOption {
              type = str;
              default = "JetBrainsMono Nerd Font";
              example = "FiraCode Nerd Font";
            };
          };
        });
      };

      hyprland = mkOption {
        type = nullOr (submodule {
          options = {
            package = mkPackageOption pkgs "hyprland" { };

            monitorConfig = mkOption {
              type = lines;
              default = "";
              example = ''
                env = GDK_SCALE,1
                monitor=,preferred,auto,1
              '';
            };

            widerWindowGaps = mkEnableOption "Enable wider gaps than default.";

            roundWindowCorners = mkEnableOption "Enable rounded window corners";

            dwindleExtra = mkOption {
              type = lines;
              default = "";
              description = "Extra options for dwindle layout, such as setting an aspect ratio for single-window workspaces";
              example = ''
                single_window_aspect_ratio = 16 9
              '';
            };

            bindings = mkOption {
              type = listOf str;
              default = [ ];
              description = "Keybindings to add to the Hyprland configuration.";
              example = [ "bindd = CTRL, F11, Melt Faces, exec, repeat_key_toggle" ];
            };

            bindingsExtra = mkOption {
              type = lines;
              default = "";
              description = "Extra keybindings to add to the Hyprland configuration (raw lines).";
              example = ''
                bindd = CTRL, F11, Melt Faces, exec, repeat_key_toggle
              '';
            };

            envs = mkOption {
              type = attrsOf str;
              default = { };
              description = "Environment variables to add to the Hyprland configuration.";
              example = {
                YDOTOOL_SOCKET = "/run/ydotool/socket";
              };
            };

            envsExtra = mkOption {
              type = lines;
              default = "";
              description = "Extra environment variables to add to the Hyprland configuration (raw lines).";
              example = ''
                env = YDOTOOL_SOCKET,/run/ydotool/socket
              '';
            };
          };
        });
      };

      keyboard = mkOption {
        type = nullOr (submodule {
          options = {
            layout = mkOption {
              type = str;
              default = "us";
            };
            variant = mkOption {
              type = nullOr str;
              default = null;
              example = "dvorak";
            };
            options = mkOption {
              type = nullOr str;
              default = "compose:caps";
              example = "compose:ralt";
            };
          };
        });
      };

      passwordManager = mkOption {
        type = str;
        default = "1password";
        example = "bitwarden";
        description = "The password manager to use.";
      };

      screensaver = mkOption {
        type = nullOr (submodule {
          options = {
            activationMinutes = mkOption {
              type = oneOf [
                float
                int
              ];
              default = 2.5;
              example = 10;
              description = "Minutes of inactivity before activating the screensaver.";
            };
            lockMinutes = mkOption {
              type = oneOf [
                float
                int
              ];
              default = 2.5166667; # default is to lock 1 second after screensaver activation
              example = 15;
              description = "Minutes of inactivity before locking the screen.";
            };
            screenOffDelaySeconds = mkOption {
              type = int;
              default = 179; # default is 5.5 mins, 3 mins after activation
              example = 60;
              description = "How long to wait after locking before turning off screen.";
            };
          };
        });
      };

      terminal = mkOption {
        type = enum [
          "ghostty"
          "kitty"
          "alacritty"
        ];
        default = "ghostty";
      };

      theme = mkOption {
        type = enum (attrNames (readDir ../../../themes));
        default = "tokyo-night";
      };

      lightMode = mkOption {
        type = bool;
        internal = true;
        default = pathExists (../../../themes + "/${config.omarchy.theme}/light.mode");
      };

      palette = mkOption {
        type = types.attrs;
        description = "Palette of the selected theme";
        default =
          let
            raw = importTOML (../../../themes + "/${config.omarchy.theme}/colors.toml");
            # TODO: the robot wrote this, surely it exists already?
            hexToDec =
              v:
              let
                hexToInt =
                  x:
                  let
                    c = toUpper x;
                    map = {
                      "0" = 0;
                      "1" = 1;
                      "2" = 2;
                      "3" = 3;
                      "4" = 4;
                      "5" = 5;
                      "6" = 6;
                      "7" = 7;
                      "8" = 8;
                      "9" = 9;
                      "A" = 10;
                      "B" = 11;
                      "C" = 12;
                      "D" = 13;
                      "E" = 14;
                      "F" = 15;
                    };
                  in
                  map.${c};
                chars = stringToCharacters v;
                len = length chars;
              in
              if len == 1 then
                hexToInt (head chars)
              else if len == 2 then
                (hexToInt (head chars)) * 16 + (hexToInt (elemAt chars 1))
              else
                throw "hexToDec only supports 1 or 2 chars";

            hexToRgb =
              hex:
              "${toString (hexToDec (substring 0 2 hex))},${toString (hexToDec (substring 2 2 hex))},${
                toString (hexToDec (substring 4 2 hex))
              }";
            strip = hex: removePrefix "#" hex;
          in
          concatMapAttrs (
            name: value:
            if hasPrefix "#" value then
              {
                "${name}" = value;
                "${name}_strip" = strip value;
                "${name}_rgb" = hexToRgb (strip value);
              }
            else
              { "${name}" = value; }
          ) raw;
        readOnly = true;
      };

      twelveHourClock = mkOption {
        type = bool;
        default = true;
        description = "Show am/pm in Waybar";
      };

      voxtype = mkOption {
        type = nullOr (submodule {
          options = {
            variant = mkOption {
              type = enum [
                "default"
                "vulkan"
                "rocm"
              ];
              default = "default";
              description = ''
                Which voxtype build variant to use.
                - default: CPU-only inference
                - vulkan: GPU via Vulkan (cross-vendor)
                - rocm: GPU via ROCm (AMD-only, faster
                  for ML workloads on AMD cards)
              '';
            };
            model = mkOption {
              type = enum [
                "tiny"
                "tiny.en"
                "base"
                "base.en"
                "small"
                "small.en"
                "medium"
                "medium.en"
                "large-v3"
                "large-v3-turbo"
              ];
              default = "base.en";
              description = ''
                Whisper model for transcription. The .en
                variants are English-only but faster.
                large-v3-turbo is recommended for GPU.
              '';
            };
            ydotool = mkPackageOption pkgs "ydotool" { };
            audioFeedback = mkOption {
              type = nullOr (submodule {
                options = {
                  theme = mkOption {
                    type = str;
                    default = "default";
                    example = "subtle";
                    description = ''
                      Sound theme: "default", "subtle",
                      "mechanical", or path to custom theme
                      directory.
                    '';
                  };
                  volume = mkOption {
                    type = float;
                    default = 0.7;
                    description = "Volume level (0.0 to 1.0).";
                  };
                };
              });
              default = null;
              description = "Audio feedback sounds config.";
            };
          };
        });
        default = null;
        description = "Voxtype push-to-talk voice-to-text.";
      };
    };
  };

  config = mkIf config.omarchy.enable {
    omarchy = {
      browser = mkDefault { };
      font = mkDefault { };
      hyprland = mkDefault { };
      keyboard = mkDefault { };
      # palette = mkDefault { };
      screensaver = mkDefault { };
    };
  };
}
