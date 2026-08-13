# Making your own theme

You can add your own themes to `~/.config/omarchy/themes`. Just copy one of the existing ones as a base (look in `~/.local/share/omarchy/themes`), then tweak to your delight. As long as your theme is inside that folder, it'll be included in the theme selection menu.

The main file you have to tweak is `colors.toml`. That defines the color set that's then used to generate configurations for the terminal (Ghostty/Alacritty/Kitty), btop, Chromium, Hyprland, Hyprlock, Mako, SwayOSD, Walker, and Waybar.

You can also use the included Aether application to create a new theme using a lovely GUI interface to play with colors and search for backgrounds. Just start it via the app launcher on `Super + Space`.

### Light mode

If you're making a light mode theme, drop an empty file called `light.mode` in the root of your theme. Then it'll automatically be paired with light mode for all the apps.

### Icon colors

If you'd like to color-match the file manager icons to your theme, add a file called `icons.theme` with the name of the icon set you want to you. By default, the options are: `Yaru Yaru-blue Yaru-dark Yaru-magenta Yaru-olive Yaru-prussiangreen Yaru-purple Yaru-red Yaru-sage Yaru-wartybrown Yaru-yellow`.

### Unlock image

Themes supplied with `unlock.png` and `preview-unlock.png` images will be listed under _Style > Unlock_. Your `unlock.png` should preferably be a transparent png. And you can create the preview image using `omarchy plymouth preview`.

### Distributing your theme

If you want to distribute your theme so others can use it, you need to put it on a public git server, like GitHub. Then people can install it using _Install > Theme_ in the Omarchy menu using that URL. It's recommended that you follow the naming convention of `omarchy-[themename]-theme`, as the theme will show correctly as just `[themename]` in the theme selection menu after installation.

You can have your theme added to [the extra themes page](36-extra-themes.md) by pinging @tahayvr on [the #omarchy Discord](https://discord.gg/tXFUdasqhY).
