# Themes, Backgrounds, and Fonts

Read this before changing themes, backgrounds, fonts, or theme colors.

## Theme Commands

```bash
omarchy theme list              # Show available themes
omarchy theme current           # Show current theme
omarchy theme set <name>        # Apply theme ("Tokyo Night" and "tokyo-night" both work)
omarchy theme bg next           # Cycle background
omarchy theme install <url>     # Install from git repo
```

## Making a New Theme

1. Create a directory under `~/.config/omarchy/themes`.
2. See how an existing theme is done via `/usr/share/omarchy/themes/catppuccin`.
3. Download a matching background (or several) from the internet and put them in `~/.config/omarchy/themes/<name-of-new-theme>/backgrounds/`.
4. When done with the theme, run `omarchy theme set "Name of new theme"`.

Additional user backgrounds for any theme (stock or custom) go in
`~/.config/omarchy/backgrounds/<theme-slug>/`.

## What a Theme Under `~/.config/omarchy/themes` May Contain

Only `colors.toml`, `light.mode`, `preview.png`, `preview-unlock.png`,
`unlock.png`, and images under `backgrounds/`. Anything else in that directory
is ignored when the theme is applied, and named on stderr.

`omarchy theme install <url>` clones a stranger's repo into that directory, and
nothing on disk tells that apart from a theme written by hand, so both are held
to the same list. Most themed files are code: a theme's `hyprland.lua` is Lua
Hyprland runs at login and a terminal config names the program the terminal
launches. Every one of them is generated from `colors.toml` through
`$OMARCHY_PATH/default/themed/*.tpl` instead.

To change how Omarchy themes an app, write the template, not the theme: a file
at `~/.config/omarchy/themed/<config-name>.tpl` overrides the built-in one and
applies to every theme. See `docs/theming.md` in the Omarchy repo.

## Customizing a Stock Theme

Never edit stock themes under `/usr/share/omarchy/themes/` — changes are lost
on update. Two safe options:

**Overlay (preferred for small tweaks):** create a user theme directory with
the SAME slug containing only the palette you want to change. When the theme is
applied, the stock theme is copied first and your `colors.toml` wins on top:

```bash
mkdir -p ~/.config/omarchy/themes/catppuccin
cp /usr/share/omarchy/themes/catppuccin/colors.toml ~/.config/omarchy/themes/catppuccin/
# Edit the copied colors.toml, then re-apply:
omarchy theme set catppuccin
```

**Fork:** copy a stock theme's palette and backgrounds under a new name for a
fully independent variant:

```bash
mkdir -p ~/.config/omarchy/themes/catppuccin-custom
cp -r /usr/share/omarchy/themes/catppuccin/{colors.toml,backgrounds} ~/.config/omarchy/themes/catppuccin-custom/
# Edit ~/.config/omarchy/themes/catppuccin-custom/colors.toml, then:
omarchy theme set catppuccin-custom
```

## Fonts

```bash
omarchy font list               # Available fonts
omarchy font current            # Current font
omarchy font set <name>         # Change font
```
