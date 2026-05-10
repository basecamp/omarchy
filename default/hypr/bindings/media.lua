-- Volume, brightness, keyboard backlight, and touchpad controls.
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("omarchy-swayosd-client --output-volume raise"), { locked = true, repeating = true, description = "Volume up" })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("omarchy-swayosd-client --output-volume lower"), { locked = true, repeating = true, description = "Volume down" })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("omarchy-swayosd-client --output-volume mute-toggle"), { locked = true, repeating = true, description = "Mute" })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("omarchy-audio-input-mute"), { locked = true, repeating = true, description = "Mute microphone" })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("omarchy-brightness-display +5%"), { locked = true, repeating = true, description = "Brightness up" })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("omarchy-brightness-display 5%-"), { locked = true, repeating = true, description = "Brightness down" })
hl.bind("SHIFT + XF86MonBrightnessUp", hl.dsp.exec_cmd("omarchy-brightness-display 100%"), { locked = true, repeating = true, description = "Brightness maximum" })
hl.bind("SHIFT + XF86MonBrightnessDown", hl.dsp.exec_cmd("omarchy-brightness-display 1%"), { locked = true, repeating = true, description = "Brightness minimum" })
hl.bind("XF86KbdBrightnessUp", hl.dsp.exec_cmd("omarchy-brightness-keyboard up"), { locked = true, repeating = true, description = "Keyboard brightness up" })
hl.bind("XF86KbdBrightnessDown", hl.dsp.exec_cmd("omarchy-brightness-keyboard down"), { locked = true, repeating = true, description = "Keyboard brightness down" })
hl.bind("XF86KbdLightOnOff", hl.dsp.exec_cmd("omarchy-brightness-keyboard cycle"), { locked = true, description = "Keyboard backlight cycle" })
hl.bind("XF86TouchpadToggle", hl.dsp.exec_cmd("omarchy-toggle-touchpad"), { locked = true, description = "Toggle touchpad" })
hl.bind("XF86TouchpadOn", hl.dsp.exec_cmd("omarchy-toggle-touchpad on"), { locked = true, description = "Enable touchpad" })
hl.bind("XF86TouchpadOff", hl.dsp.exec_cmd("omarchy-toggle-touchpad off"), { locked = true, description = "Disable touchpad" })

-- Precise volume and brightness controls.
hl.bind("ALT + XF86AudioRaiseVolume", hl.dsp.exec_cmd("omarchy-swayosd-client --output-volume +1"), { locked = true, repeating = true, description = "Volume up precise" })
hl.bind("ALT + XF86AudioLowerVolume", hl.dsp.exec_cmd("omarchy-swayosd-client --output-volume -1"), { locked = true, repeating = true, description = "Volume down precise" })
hl.bind("ALT + XF86MonBrightnessUp", hl.dsp.exec_cmd("omarchy-brightness-display +1%"), { locked = true, repeating = true, description = "Brightness up precise" })
hl.bind("ALT + XF86MonBrightnessDown", hl.dsp.exec_cmd("omarchy-brightness-display 1%-"), { locked = true, repeating = true, description = "Brightness down precise" })

-- Media controls.
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("omarchy-swayosd-client --playerctl next"), { locked = true, description = "Next track" })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("omarchy-swayosd-client --playerctl play-pause"), { locked = true, description = "Pause" })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("omarchy-swayosd-client --playerctl play-pause"), { locked = true, description = "Play" })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("omarchy-swayosd-client --playerctl previous"), { locked = true, description = "Previous track" })

hl.bind("SUPER + XF86AudioMute", hl.dsp.exec_cmd("omarchy-audio-output-switch"), { locked = true, description = "Switch audio output" })
