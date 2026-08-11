# Themes, Backgrounds, and Fonts

Use this guide for selecting, installing, creating, or customizing themes,
backgrounds, colors, and fonts.

## Select or Install

Prefer theme commands for ordinary changes:

```bash
omarchy theme list
omarchy theme current
omarchy theme set <name>
omarchy theme bg next
omarchy theme install <url>

omarchy font list
omarchy font current
omarchy font set <name>
```

Selection is complete when the corresponding `current` command reports the
requested value and the affected desktop surfaces visibly use it. Mark visual
verification explicitly if the harness cannot inspect the desktop.

## Choose a Customization Shape

Choose one shape before editing:

- **Overlay** — small changes to a stock theme. Create the same theme slug under `~/.config/omarchy/themes/` and include only changed files; user files override packaged files.
- **Fork** — an independent variant of a stock theme. Copy the complete packaged theme to a new user-owned slug.
- **New theme** — a theme designed without a stock base. Create a new user-owned slug and supply its required files.

Use an overlay unless the requested result needs an independently named or
fully divergent theme.

## Overlay a Stock Theme

```bash
mkdir -p ~/.config/omarchy/themes/catppuccin
cp "$OMARCHY_PATH/themes/catppuccin/colors.toml" ~/.config/omarchy/themes/catppuccin/
# Edit the user-owned colors.toml, then apply the merged theme:
omarchy theme set catppuccin
```

The packaged theme is staged first and same-slug user files win. Keep unchanged
files in the packaged theme so updates can improve them.

## Fork a Stock Theme

```bash
cp -r "$OMARCHY_PATH/themes/catppuccin" ~/.config/omarchy/themes/catppuccin-custom
# Edit the user-owned copy, then apply it:
omarchy theme set catppuccin-custom
```

## Create a New Theme

1. Create `~/.config/omarchy/themes/<theme-slug>/`.
2. Inspect a packaged theme such as `$OMARCHY_PATH/themes/catppuccin/` for the current shape.
3. Add the theme files required for the requested surfaces.
4. Put theme-owned images in `~/.config/omarchy/themes/<theme-slug>/backgrounds/`.
5. Apply with `omarchy theme set <theme-slug>`.

Additional user backgrounds for a stock or custom theme go in
`~/.config/omarchy/backgrounds/<theme-slug>/`.

## Completion and Recovery

Theme customization is complete when:

- `omarchy theme current` reports the expected theme;
- every changed file is under `~/.config/omarchy/`;
- the requested colors, background, and font render on every affected surface;
- no unrelated packaged theme file was copied into an overlay.

To reverse an overlay, remove only its user-owned changed files and reapply the
stock theme. To reverse a fork or new theme, select another theme before
removing its user directory. Obtain confirmation before deleting user theme
files.
