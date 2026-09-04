# Backgrounds

Every theme ships with its own set of backgrounds, and you can add extras of your own in `~/.config/omarchy/backgrounds/[theme]`. If you want to add an extra background image to, say, the nord theme, you just put the file in `~/.config/omarchy/backgrounds/nord`.

You can do this most easily by going to _Install > Style > Background_ in the Omarchy Menu. That'll bring up the folder where the backgrounds for that theme is stored. Hit `Super + Shift + F` to start another file manager, find your background, copy it over.  Now it'll be included in the choices of backgrounds you can select between using `Super + Ctrl + Space`.

You can find a huge collection of cool curated backgrounds on https://github.com/dharmx/walls.

## Different backgrounds on different monitors

Add an optional `background` object to `~/.config/omarchy/shell.json`, alongside the existing `version`, `bar`, and other settings:

```json
"background": {
  "monitors": {
    "DP-1": "~/Pictures/backgrounds/main.jpg"
  },
  "portrait": "~/Pictures/backgrounds/vertical.jpg",
  "landscape": "~/Pictures/backgrounds/horizontal.jpg"
}
```

Use the monitor names shown by `hyprctl monitors`. All settings are optional. A named monitor takes precedence over the orientation default; displays without either use the current theme background. Portrait means the display is taller than it is wide after rotation; square displays use the landscape setting. Selection updates when displays connect, rotate, or change size.

Use absolute paths or paths starting with `~/`; spaces and special characters are supported. If a selected override is invalid, missing, unreadable, or cannot be decoded as an image, that display uses the current theme background. An invalid named override falls back directly to the theme, rather than the orientation default.

Theme changes and background cycling continue to change the normal theme background. Overrides stay fixed, while theme colors still update throughout the desktop. Each display retains the normal aspect-preserving crop and reveal effect. Saving `shell.json` updates the settings without restarting the desktop; remove a setting to return to its usual fallback. With no `background` settings, behavior is unchanged.
