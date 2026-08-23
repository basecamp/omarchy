# Backgrounds

Every theme ships with its own set of backgrounds, and you can add extras of your own in `~/.config/omarchy/backgrounds/[theme]`. If you want to add an extra background image to, say, the nord theme, you just put the file in `~/.config/omarchy/backgrounds/nord`.

You can do this most easily by going to _Install > Style > Background_ in the Omarchy Menu. That'll bring up the folder where the backgrounds for that theme is stored. Hit `Super + Shift + F` to start another file manager, find your background, copy it over.  Now it'll be included in the choices of backgrounds you can select between using `Super + Ctrl + Space`.

You can find a huge collection of cool curated backgrounds on https://github.com/dharmx/walls.

## Wallpaper memory

On systems with less than 4 GiB of available memory, Omarchy automatically
decodes wallpapers at a bounded size derived from the physical display size
instead of keeping their full source resolution in memory. The current
low-memory test factor is 16, so a 1366x768 display requests an approximately
85x48 source image. The behavior is automatic and requires no setting; when
more memory is available, wallpapers keep their current full-resolution
behavior.
