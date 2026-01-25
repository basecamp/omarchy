# Export an omarchy theme for stylix
#
# Usage:
#   # Option 1: Let stylix generate colors from the wallpaper (recommended)
#   stylix.image = (omarchy.stylixTheme { theme = "ethereal"; inherit lib; }).image;
#
#   # Option 2: Use best-effort base16 mapping from omarchy palette
#   stylix.base16Scheme = (omarchy.stylixTheme { theme = "ethereal"; inherit lib; }).base16Scheme;
{
  theme,
  lib,
}:
with builtins;
let
  strip = hex: lib.removePrefix "#" hex;

  raw = lib.importTOML ../../themes/${theme}/colors.toml;

  # Build palette with _strip variants like omarchy's home module does
  palette = lib.concatMapAttrs (
    name: value:
    if lib.hasPrefix "#" value then
      {
        "${name}" = value;
        "${name}_strip" = strip value;
      }
    else
      { "${name}" = value; }
  ) raw;

  p = palette;
  backgroundsDir = ../../themes/${theme}/backgrounds;
  firstBackground = head (lib.naturalSort (attrNames (readDir backgroundsDir)));
  isLightTheme = pathExists (../../themes/${theme}/light.mode);
in
{
  # "dark" or "light" - for stylix.polarity
  polarity = if isLightTheme then "light" else "dark";

  # Background image - stylix can generate colors from this
  image = path { path = backgroundsDir + "/${firstBackground}"; };

  # Best-effort base16 mapping from ANSI terminal colors
  # Note: omarchy's color0-15 are ANSI colors, not a grayscale gradient,
  # so base01-04/06-07 use approximations from available grays
  base16Scheme = {
    scheme = theme;
    author = "omarchy";

    # Grayscale shades (using available grays: background, color0, color8, color7, color15, foreground)
    base00 = p.background_strip; # background
    base01 = p.color0_strip; # black (often same as bg)
    base02 = p.color8_strip; # bright black / gray
    base03 = p.color8_strip; # comments (reuse gray)
    base04 = p.color7_strip; # white as mid-tone
    base05 = p.foreground_strip; # foreground
    base06 = p.color7_strip; # white
    base07 = p.color15_strip; # bright white

    # Accent colors (ANSI semantic mapping)
    base08 = p.color1_strip; # red - errors, deletions
    base09 = p.color9_strip; # bright red - constants (orange substitute)
    base0A = p.color3_strip; # yellow - warnings, classes
    base0B = p.color2_strip; # green - strings, success
    base0C = p.color6_strip; # cyan - regex, info
    base0D = p.color4_strip; # blue - functions
    base0E = p.color5_strip; # magenta - keywords
    base0F = p.color9_strip; # bright red (brown substitute)
  };
}
