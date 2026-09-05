# Backgrounds

Every theme ships with its own set of backgrounds, and you can add extras of your own in `~/.config/omarchy/backgrounds/[theme]`. If you want to add an extra background image to, say, the nord theme, you just put the file in `~/.config/omarchy/backgrounds/nord`.

You can do this most easily by going to _Install > Style > Background_ in the Omarchy Menu. That'll bring up the folder where the backgrounds for that theme is stored. Hit `Super + Shift + F` to start another file manager, find your background, copy it over.  Now it'll be included in the choices of backgrounds you can select between using `Super + Ctrl + Space`.

Backgrounds can be videos as well as stills. Drop an `mp4`, `m4v`, `mov`, `webm`, `mkv`, or `avi` file in the same folder and it appears alongside the images, playing muted and looped. Playback stops on its own whenever nothing can see it — while a fullscreen window is focused, while the screensaver is up, and once a locked screen has gone dark — but a video wallpaper still costs far more power than a still one, and each monitor decodes its own copy.

A still background can have a short boot intro that plays once per system boot and ends on the already-loaded image. Use _Style > Boot Intro > Set Intro_ to choose a video for the current background. Omarchy stores it separately from regular backgrounds, so it stays out of the background picker and never loops.

Boot intros are bound to the exact contents of a background rather than only its filename. Replacing an image with a different one under the same name therefore cannot play a mismatched intro. _Remove Intro_ removes your intro and suppresses any default supplied by the theme; _Restore Default_ allows the theme's intro again. Use the _Enabled_ switch to turn all boot intros on or off.

Theme authors can include a default intro such as `intros/0-winding-road.mp4` with a matching `intros/0-winding-road.sha256`. The checksum file contains the SHA-256 of `backgrounds/0-winding-road.webp`.

You can find a huge collection of cool curated backgrounds on https://github.com/dharmx/walls.
