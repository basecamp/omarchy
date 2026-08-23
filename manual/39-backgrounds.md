# Backgrounds

Every theme ships with its own set of backgrounds, and you can add extras of your own in `~/.config/omarchy/backgrounds/[theme]`. If you want to add an extra background image to, say, the nord theme, you just put the file in `~/.config/omarchy/backgrounds/nord`.

You can do this most easily by going to _Install > Style > Background_ in the Omarchy Menu. That'll bring up the folder where the backgrounds for that theme is stored. Hit `Super + Shift + F` to start another file manager, find your background, copy it over.  Now it'll be included in the choices of backgrounds you can select between using `Super + Ctrl + Space`.

You can find a huge collection of cool curated backgrounds on https://github.com/dharmx/walls.

## Wallpaper memory

When Omarchy starts with less than 4 GiB of available memory, it automatically decodes wallpapers at a crop-aware size derived from the physical display instead of keeping their full source resolution in memory. The decision is made once per shell startup and requires no setting; when more memory is available at startup, wallpapers keep their current full-resolution behavior. This is intentionally conservative: when a source is larger than the display, the display-sized decode avoids retaining detail that cannot be shown, while smaller sources are not enlarged.
