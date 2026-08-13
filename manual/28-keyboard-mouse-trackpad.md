# Keyboard, Mouse, Trackpad

Hyprland let's you configure all your inputs in great detail. You can change the keyboard repeat to be supersonically fast or make the trackpad use natural scrolling. You change all of it in `~/.config/hypr/input.conf`, which you can also reach via _Setup > Input_ in the Omarchy menu (`Super + Alt + Space`).

Here's an example:

```
input {
  # Use multiple keyboard layouts and switch between them with Alt + Space
  kb_layout = us,dk
  kb_options = compose:caps,grp:alt_space_toggle

  # Change speed of keyboard repeat
  repeat_rate = 40
  repeat_delay = 600

  # Increase sensitity for mouse/trackpack (default: 0)
  sensitivity = 0.35

  touchpad {
    # Use natural (inverse) scrolling
    natural_scroll = true

    # Use two-finger clicks for right-click instead of lower-right corner
    clickfinger_behavior = true

    # Control the speed of your scrolling
    scroll_factor = 0.3
  }
}

# Scroll faster in the terminal
windowrule = scrolltouchpad 1.5, tag:terminal
```

You can [see all the input options](https://wiki.hypr.land/Configuring/Basics/Variables/#input) on the Hyprland wiki for inputs.

### Use ALT as SUPER

On some keyboards, it's not convenient to use the primary meta key (Windows/cmd key) as SUPER. You can change this to be ALT instead using this change:

```
input {
  kb_options = compose:caps,altwin:swap_alt_win
}
```
