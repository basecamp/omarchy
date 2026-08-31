# Making your own theme

You can add your own themes to `~/.config/omarchy/themes`. Just copy one of the existing ones as a base (look in `/usr/share/omarchy/themes`), then tweak to your delight. As long as your theme is inside that folder, it'll be included in the theme selection menu.

The main file you have to tweak is `colors.toml`. That defines the color set that's then used to generate configurations for the terminal (Foot/Alacritty/Ghostty/Kitty), btop, Chromium, Hyprland, Neovim, Helix, VSCode, Obsidian, and the entire Omarchy shell (top bar, menu, notifications, OSD, and lock screen).

You can also use the included Aether application to create a new theme using a lovely GUI interface to play with colors and search for backgrounds. Just start it via the apps menu on `Super + Alt + Space`.

### What an installed theme can contain

A theme you write yourself in `~/.config/omarchy/themes` can contain whatever you like — it's your machine and your file, and Omarchy applies all of it.

A theme you install from someone else's repo with `omarchy theme install` keeps everything that's colour, and loses the handful of files that would run code on your machine: any `.lua` file, the terminal configs (`alacritty.toml`, `foot.ini`, `ghostty.conf`, `kitty.conf`), and `vscode.json`. A theme's `hyprland.lua` is Lua your compositor runs at login, a terminal config names the program your terminal starts, and `vscode.json` names a VSCode extension to install. Installing someone's theme should change what your desktop looks like, never what it runs.

Everything else still works exactly as the theme author wrote it — `btop.theme`, `chromium.theme`, `helix.toml`, `icons.theme`, `shell.toml`, the backgrounds and the previews are all kept. Only what was dropped gets regenerated from `colors.toml` on your machine.

Omarchy tells the two apart by whether the theme has its own git repo inside it, which is what `omarchy theme install` leaves behind when it clones. So a theme you wrote stays yours, and one you pulled off the internet stays colours.

### Light mode

If you're making a light mode theme, set `mode = "light"` at the top of your `colors.toml`. Then it'll automatically be paired with light mode for all the apps. (The old way of dropping an empty file called `light.mode` in the root of your theme still works too.)

### Icon colors

If you'd like to color-match the file manager icons to your theme, add a file called `icons.theme` with the name of the icon set you want to use. By default, the options are: `Yaru Yaru-blue Yaru-dark Yaru-magenta Yaru-olive Yaru-prussiangreen Yaru-purple Yaru-red Yaru-sage Yaru-wartybrown Yaru-yellow`.

### Unlock image

Themes supplied with `unlock.png` and `preview-unlock.png` images will be listed under _Style > Unlock_. Your `unlock.png` should preferably be a transparent png. And you can create the preview image using `omarchy plymouth preview`.

### Theming apps Omarchy doesn't cover

If you use an app that isn't in that list, you can teach Omarchy to theme it yourself with a template. Drop a file in `~/.config/omarchy/themed/` named after the config it generates plus a `.tpl` extension, and write the config with `{{ background }}`, `{{ foreground }}`, `{{ accent }}`, `{{ red }}`, `{{ color0 }}` through `{{ color15 }}`, and the rest of the palette as placeholders. Every time you switch themes, the file is regenerated with that theme's colors.

There's a fully commented `alacritty.toml.tpl.sample` in that folder to copy from — it lists every variable you can use, plus the `_strip` and `_rgb` modifiers for apps that want their colors without the `#` or as decimal RGB. Your templates take priority over Omarchy's own, so you can also use this to override how a built-in app gets themed.

### Distributing your theme

If you want to distribute your theme so others can use it, you need to put it on a public git server, like GitHub. Then people can install it using _Install > Style > Theme_ in the Omarchy menu using that URL. It's recommended that you follow the naming convention of `omarchy-[themename]-theme`, as the theme will show correctly as just `[themename]` in the theme selection menu after installation.

That leftover `[themename]` becomes the theme's directory name, so it has to be one Omarchy can hand around safely: it must start with a letter, a digit, or an underscore, and the rest may hold letters, digits, `.`, `_`, `+`, and `-`. Capitals are lowercased for you, but anything else — a space, a quote, a non-English character — is refused at install time rather than turned into a directory name. So `omarchy-tokyo-night-theme`, `omarchy-flexoki_light-theme`, and `omarchy-c++-theme` all install fine.

Remember that once it's installed from a repo, any `.lua`, terminal config or `vscode.json` it ships is dropped, so don't build the theme around those.

You can have your theme added to [the extra themes page](https://omarchy.org/themes/) by sending a pull request to [the omarchy-site repo](https://github.com/omacom-io/omarchy-site).
