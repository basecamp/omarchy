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

## What a Theme Installed From a Repo May Not Contain

A theme the user wrote by hand in `~/.config/omarchy/themes` is unrestricted, as
are Omarchy's own themes. From a theme cloned by `omarchy theme install`, Omarchy
drops only what runs code: any `*.lua` (Hyprland requires a theme's
`hyprland.lua` and `gum_env.lua` at login, Neovim loads `neovim.lua` at startup),
the terminal configs `alacritty.toml`, `foot.ini`, `ghostty.conf` and
`kitty.conf` (each names the program the terminal launches), and `vscode.json`
(names a VS Code extension to install). Those are regenerated from `colors.toml`
through `$OMARCHY_PATH/default/themed/*.tpl`, and named on stderr.

Everything else a cloned theme ships is kept, including `btop.theme`,
`chromium.theme`, `helix.toml`, `icons.theme`, `keyboard.rgb` and `shell.toml`.
Omarchy tells a cloned theme from the user's own by the `.git` directory a clone
leaves behind.

To change how Omarchy themes an app for every theme, write the template rather
than the theme: `~/.config/omarchy/themed/<config-name>.tpl` overrides the
built-in one. See `docs/theming.md` in the Omarchy repo.

## Customizing a Stock Theme

Never edit stock themes under `/usr/share/omarchy/themes/` — changes are lost
on update. Two safe options:

Both write into `~/.config/omarchy/themes`, where a theme the user wrote is
unrestricted — the list above applies only to a theme cloned from a repo.

**Overlay (preferred for small tweaks):** create a user theme directory with
the SAME slug containing only the files you want to change. When the theme is
applied, the stock theme is copied first and your files win on top:

```bash
mkdir -p ~/.config/omarchy/themes/catppuccin
cp /usr/share/omarchy/themes/catppuccin/colors.toml ~/.config/omarchy/themes/catppuccin/
# Edit the copied colors.toml, then re-apply:
omarchy theme set catppuccin
```

**Fork:** copy the whole stock theme under a new name for a fully independent
variant:

```bash
cp -r /usr/share/omarchy/themes/catppuccin ~/.config/omarchy/themes/catppuccin-custom
# Edit ~/.config/omarchy/themes/catppuccin-custom/, then:
omarchy theme set catppuccin-custom
```

## Making Backgrounds Fit Different Screens

Theme backgrounds live in the theme's `backgrounds/` directory (user extras in
`~/.config/omarchy/backgrounds/<theme-slug>/`). By default an image is cropped to
cover the screen. Three tools adjust that, per directory:

- **Aspect-ratio variants:** a sibling file named `<stem>@<label>.<ext>`
  (`forest@ultrawide.png` next to `forest.png`) is shown automatically on
  whichever monitor its pixel aspect ratio matches best. Variants never appear
  in choosers and are never set directly — always set the base file.
- **`backgrounds.toml`** in the same directory as the images: a `[defaults]`
  section plus optional per-image sections named by the image's filename minus
  its extension. Keys: `fill = "crop" | "fit" | "center" | "tile"` (default
  `crop`), `fill_color = "<colors.toml key>"` or `"#rrggbb"` (default
  `background`; pads `fit`/`center`/`tile`), and `focal = "x y"` in 0..1 — the
  point kept in view when cropping (default `"0.5 0.5"`).
- **SVG backgrounds:** `.svg` files work as backgrounds and are rasterized
  crisply per screen. A theme can also ship `backgrounds/*.svg.tpl` templates
  using the standard `{{ key }}` placeholders; they render to `.svg` with the
  theme's palette when the theme is applied, and a same-named `.svg` shipped by
  the theme wins over the template.

## Fonts

```bash
omarchy font list               # Available fonts
omarchy font current            # Current font
omarchy font set <name>         # Change font
```
