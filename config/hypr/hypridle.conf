general {
    lock_cmd = omarchy-lock-screen                         # lock screen and 1password
    before_sleep_cmd = loginctl lock-session               # lock before suspend.
    after_sleep_cmd = sleep 1 && hyprctl dispatch dpms on  # delay for PAM readiness, then turn on display.
    inhibit_sleep = 3                                      # wait until screen is locked
}

listener {
    timeout = 150                                             # 2.5min
    on-timeout = pidof hyprlock || omarchy-launch-screensaver # start screensaver (if we haven't locked already)
}

listener {
    timeout = 151                      # 5min
    on-timeout = loginctl lock-session # lock screen when timeout has passed
}

listener {
    timeout = 330                                            # 5.5min
    on-timeout = brightnessctl -sd '*::kbd_backlight' set 0  # save state and turn off keyboard backlight
    on-resume = brightnessctl -rd '*::kbd_backlight'         # restore keyboard backlight
}

listener {
    timeout = 330                                            # 5.5min
    on-timeout = hyprctl dispatch dpms off                   # screen off when timeout has passed
    on-resume = hyprctl dispatch dpms on && brightnessctl -r # screen on when activity is detected
}
