# Backgrounds

Every theme ships with its own set of backgrounds, and you can add extras of your own in `~/.config/omarchy/backgrounds/[theme]`. If you want to add an extra background image to, say, the nord theme, you just put the file in `~/.config/omarchy/backgrounds/nord`.

You can do this most easily by going to _Install > Style > Background_ in the Omarchy Menu. That'll bring up the folder where the backgrounds for that theme is stored. Hit `Super + Shift + F` to start another file manager, find your background, copy it over.  Now it'll be included in the choices of backgrounds you can select between using `Super + Ctrl + Space`.

You can find a huge collection of cool curated backgrounds on https://github.com/dharmx/walls.

### Making backgrounds fit your screen

Backgrounds are scaled to fill the whole screen by default, cropping off whatever doesn't fit. That looks great on a regular 16:9 display, but on an ultrawide or a portrait monitor it can cut away half the picture. A few ways to fix that, all of which work in your own background folders too:

**Ship a variant for that screen shape.** Put a second version of the image next to the original, named after it plus an `@` label: `forest@ultrawide.png` beside `forest.png`. You still just pick `forest` as your background — Omarchy shows whichever version best matches each monitor's shape, so a wide screen gets the wide crop while your laptop keeps the regular one. The label itself can be anything; it's the image's actual proportions that count. Variants don't show up as separate choices in the background picker — in fact any background whose filename contains an `@` is treated as a variant and hidden from the picker, so rename files like `photo@2x.png` if you want them listed on their own.

**Letterbox instead of cropping.** Drop a `backgrounds.toml` file next to the images to say how they should be drawn:

```toml
[defaults]
fill = "fit"
fill_color = "background"
```

`fill` can be `crop` (the default), `fit` (show the whole image, padding the rest with `fill_color`), `center` (unscaled), or `tile`. `fill_color` takes a theme color name like `background` or a hex value like `"#1a1b26"`. You can also set these per image, and point the crop at the part of the picture that matters with `focal`:

```toml
["forest"]
fill = "crop"
focal = "0.65 0.4"
```

The section name is the image's filename without its extension, and `focal` is the spot to keep in view — `"0.5 0.5"` is the center, `"0.65 0.4"` keeps the point 65% across and 40% down.

**Use a responsive SVG.** SVG backgrounds stay crisp, and an SVG designed with percentage-based placement can reflow to every monitor shape without variants. Opt that file into an exact per-screen viewport in `backgrounds.toml`:

```toml
["wallpaper"]
svg_layout = "responsive"
```

The section name is the SVG filename without `.svg`. Its root `<svg>` should include `width`, `height`, and `viewBox`; Omarchy replaces those with the current screen dimensions while rendering. Nested SVG viewports can keep a logo undistorted while backgrounds and horizontal artwork expand to fill the screen.
