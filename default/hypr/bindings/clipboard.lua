hl.bind("SUPER + C", hl.dsp.send_shortcut({ mods = "CTRL", key = "Insert" }), { description = "Universal copy" })
hl.bind("SUPER + V", hl.dsp.send_shortcut({ mods = "SHIFT", key = "Insert" }), { description = "Universal paste" })
hl.bind("SUPER + X", hl.dsp.send_shortcut({ mods = "CTRL", key = "X" }), { description = "Universal cut" })
hl.bind("SUPER + CTRL + V", hl.dsp.exec_cmd("omarchy-launch-walker -m clipboard"), { description = "Clipboard manager" })
