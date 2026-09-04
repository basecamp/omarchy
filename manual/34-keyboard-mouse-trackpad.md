# Keyboard, Mouse, Trackpad

Hyprland lets you configure all your inputs in great detail. You can change the keyboard repeat to be supersonically fast or make the trackpad use natural scrolling. You change all of it in `~/.config/hypr/input.lua`, which you can also reach via _Setup > Input_ in the Omarchy menu (`Super + Space`). Anything you set there replaces Omarchy's defaults.

Here's an example:

```lua
hl.config({
  input = {
    -- Use multiple keyboard layouts and switch between them with Left Alt + Right Alt
    kb_layout = "us,dk",
    kb_options = "compose:caps,shift:both_capslock_cancel,grp:alts_toggle",

    -- Change speed of keyboard repeat
    repeat_rate = 40,
    repeat_delay = 600,

    -- Increase sensitivity for mouse/trackpad (default: 0)
    sensitivity = 0.35,

    touchpad = {
      -- Use natural (inverse) scrolling
      natural_scroll = true,

      -- Use two-finger clicks for right-click instead of lower-right corner
      clickfinger_behavior = true,

      -- Control the speed of your scrolling
      scroll_factor = 0.3,
    },
  },
})

-- Scroll faster in the terminal
o.window("(Alacritty|kitty|foot)", { scroll_touchpad = 1.5 })
```

You can [see all the input options](https://wiki.hypr.land/Configuring/Basics/Variables/#input) on the Hyprland wiki for inputs.

By default, Omarchy uses CapsLock as the compose key for [quick emojis](07-hotkeys.md#quick-emojis) and [other completions](07-hotkeys.md#quick-completions). If you'd rather use CapsLock as Caps Lock, move the compose key elsewhere by changing `compose:caps` in `kb_options`. For example, this moves the compose key to Right Alt:

```lua
hl.config({
  input = {
    kb_options = "compose:ralt",
  },
})
```

### Low-level key remapping with keyd

`kb_options` and Hyprland's bindings cover window-manager shortcuts, but they can't do physical key remapping — swapping what a key sends before it reaches Hyprland at all, tap/hold behavior on a single key, or layers. For that, install [keyd](https://github.com/rvaiya/keyd) from _Install > Service > keyd_ in the Omarchy menu (`Super + Space`), or run `omarchy-install-service-keyd`.

keyd ships with an inert starter config at `/etc/keyd/default.conf` — edit it as root, then `sudo keyd reload` to apply. A common example, tap CapsLock for Escape and hold it as a layer:

```
[ids]
*

[main]
capslock = overload(capslock, esc)

[capslock]
h = left
j = down
k = up
l = right
```

keyd intercepts keys below Hyprland and XKB, so remapping CapsLock here takes priority over the `compose:caps` option above — test that Compose still fires the way you expect before relying on both together, or move Compose to another key first. See `man keyd` for the full remapping, layer, and macro syntax.

keyd's virtual keyboard is otherwise indistinguishable from an external one, which stops libinput's disable-while-typing from suppressing the touchpad while you type. The installer adds a libinput quirk marking it internal, at `/etc/libinput/local-overrides.quirks` — a reboot is needed for it to take effect.

### Trackpad gestures

You can also turn on [touchpad gestures](https://wiki.hypr.land/Configuring/Advanced-and-Cool/Gestures/), like swiping with three fingers to change workspaces:

```lua
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
```

On Dell XPS laptops with a haptic touchpad, you can also set the click strength to low, mid, or high under _Trigger > Hardware > Touchpad Haptics_.

### Typing in Chinese, Japanese, and other languages

Omarchy runs the [fcitx5](https://fcitx-im.org/) input method framework as part of every session — it's what powers the CapsLock compose sequences. That means the plumbing for non-Latin input is already in place: install an input engine like `fcitx5-mozc` (Japanese) or `fcitx5-chinese-addons` (Chinese) with `omarchy pkg add`, plus `fcitx5-configtool` to add the engine to your input methods and set the key that switches between them.

### Use ALT as SUPER

On some keyboards, it's not convenient to use the primary meta key (Windows/cmd key) as SUPER. You can change this to be ALT instead using this change:

```lua
hl.config({
  input = {
    kb_options = "compose:caps,shift:both_capslock_cancel,altwin:swap_alt_win",
  },
})
```
