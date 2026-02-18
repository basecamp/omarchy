# Omarchy Theme Color Schema

## Purpose
Define the canonical `colors.toml` schema for themes used by Omarchy template rendering.

## Required Semantic Keys
Every theme must define these keys:

- `accent`
- `cursor`
- `foreground`
- `background`
- `selection_foreground`
- `selection_background`

## Required Base16 Keys
Every theme must define the full Base16 palette:

- `base00`
- `base01`
- `base02`
- `base03`
- `base04`
- `base05`
- `base06`
- `base07`
- `base08`
- `base09`
- `base0A`
- `base0B`
- `base0C`
- `base0D`
- `base0E`
- `base0F`

## Transitional ANSI Support
`color0` through `color15` are transitional compatibility keys.

- Existing themes may keep `color0`..`color15` during migration.
- New templates and theme authoring should target Base16 keys.
- ANSI compatibility is deprecated and scheduled for removal after migration stabilization.

## Canonical Base16 to ANSI Mapping
Use this mapping when deriving ANSI slots from Base16 values:

- `color0 = base00`
- `color1 = base08`
- `color2 = base0B`
- `color3 = base0A`
- `color4 = base0D`
- `color5 = base0E`
- `color6 = base0C`
- `color7 = base05`
- `color8 = base03`
- `color9 = base08`
- `color10 = base0B`
- `color11 = base0A`
- `color12 = base0D`
- `color13 = base0E`
- `color14 = base0C`
- `color15 = base07`

## Acceptance Gate
A theme is schema-compliant only when:

- All required semantic keys are present.
- All Base16 keys `base00`..`base0F` are present.
- No unresolved template placeholders are produced during theme application.
