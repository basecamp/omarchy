require("default.hypr.bindings_defaults")

-- Volume, brightness, keyboard backlight, and touchpad controls.
o.bind(omarchy_bindings.volume_up, "Volume up", "omarchy-audio-output-volume raise",  { locked = true, repeating = true })
o.bind(omarchy_bindings.volume_down, "Volume down", "omarchy-audio-output-volume lower",  { locked = true, repeating = true })
o.bind(omarchy_bindings.mute, "Mute", "omarchy-audio-output-volume mute-toggle",  { locked = true })
o.bind(omarchy_bindings.mute_microphone, "Mute microphone", "omarchy-audio-input-mute",  { locked = true })
o.bind(omarchy_bindings.brightness_up, "Brightness up", "omarchy-brightness-display +5%",  { locked = true, repeating = true })
o.bind(omarchy_bindings.brightness_down, "Brightness down", "omarchy-brightness-display 5%-",  { locked = true, repeating = true })
o.bind(omarchy_bindings.brightness_maximum, "Brightness maximum", "omarchy-brightness-display 100%",  { locked = true, repeating = true })
o.bind(omarchy_bindings.brightness_minimum, "Brightness minimum", "omarchy-brightness-display 1%",  { locked = true, repeating = true })
o.bind(omarchy_bindings.keyboard_brightness_up, "Keyboard brightness up", "omarchy-brightness-keyboard up",  { locked = true, repeating = true })
o.bind(omarchy_bindings.keyboard_brightness_down, "Keyboard brightness down", "omarchy-brightness-keyboard down",  { locked = true, repeating = true })
o.bind(omarchy_bindings.keyboard_backlight_cycle, "Keyboard backlight cycle", "omarchy-brightness-keyboard cycle",  { locked = true })
o.bind_toggle(omarchy_bindings.toggle_touchpad, "Toggle touchpad", "touchpad",  { locked = true })
o.bind(omarchy_bindings.enable_touchpad, "Enable touchpad", "omarchy-toggle-touchpad on",  { locked = true })
o.bind(omarchy_bindings.disable_touchpad, "Disable touchpad", "omarchy-toggle-touchpad off",  { locked = true })

-- Precise volume and brightness controls.
o.bind(omarchy_bindings.volume_up_precise, "Volume up precise", "omarchy-audio-output-volume +1",  { locked = true, repeating = true })
o.bind(omarchy_bindings.volume_down_precise, "Volume down precise", "omarchy-audio-output-volume -1",  { locked = true, repeating = true })
o.bind(omarchy_bindings.brightness_up_precise, "Brightness up precise", "omarchy-brightness-display +1%",  { locked = true, repeating = true })
o.bind(omarchy_bindings.brightness_down_precise, "Brightness down precise", "omarchy-brightness-display 1%-",  { locked = true, repeating = true })

-- Media controls.
o.bind(omarchy_bindings.next_track, "Next track", "omarchy-shell media next",  { locked = true })
o.bind(omarchy_bindings.next_track_1, "Next track", "omarchy-shell media next",  { locked = true })
o.bind(omarchy_bindings.pause, "Pause", "omarchy-shell media playPause",  { locked = true })
o.bind(omarchy_bindings.play, "Play", "omarchy-shell media playPause",  { locked = true })
o.bind(omarchy_bindings.previous_track, "Previous track", "omarchy-shell media previous",  { locked = true })
o.bind(omarchy_bindings.previous_track_2, "Previous track", "omarchy-shell media previous",  { locked = true })
o.bind(omarchy_bindings.eject_media, "Eject media", "eject",  { locked = true })

o.bind(omarchy_bindings.switch_audio_output, "Switch audio output", "omarchy-audio-output-switch",  { locked = true })
o.bind(omarchy_bindings.switch_media_source, "Switch media source", "omarchy-audio-source-switch",  { locked = true })
o.bind(omarchy_bindings.switch_media_source_3, "Switch media source", "omarchy-audio-source-switch",  { locked = true })
