-- Desktop Mode keybindings: Windows muscle memory is the API.
-- Loaded instead of tiling/utilities/applications when Ultimate mode is desktop.

o.bind("SUPER + Super_L", "Start", "omarchy-shell shell toggle omarchy.ultimate-start '{}'", { release = true })
o.bind("SUPER + S", "Search", "omarchy-shell shell summon omarchy.ultimate-start '{\"focusSearch\":true}'")
o.bind("SUPER + E", "Files", { omarchy = "nautilus" })
o.bind("SUPER + I", "Settings", "omarchy-shell shell toggle omarchy.ultimate-settings '{}'")
o.bind("SUPER + R", "Run", "omarchy-shell shell toggle omarchy.ultimate-run '{}'")
o.bind("SUPER + D", "Show desktop", "omarchy-shell window toggleShowDesktop")
o.bind("SUPER + L", "Lock", "omarchy-system-lock")
o.bind("SUPER + LEFT", "Snap window left", "omarchy-shell window snapArrow active l")
o.bind("SUPER + RIGHT", "Snap window right", "omarchy-shell window snapArrow active r")
o.bind("SUPER + UP", "Snap or maximize window", "omarchy-shell window snapArrow active u")
o.bind("SUPER + DOWN", "Snap, restore, or minimize window", "omarchy-shell window snapArrow active d")
o.bind("SUPER + Z", "Snap layout chooser", "omarchy-shell window snapChooser active")
o.bind("SUPER + SHIFT + S", "Screenshot", "omarchy-capture-screenshot")

o.bind("ALT + F4", "Close window", "omarchy-shell window closeActive")
o.bind("ALT + TAB", "Switch windows", "omarchy-shell window cycleNext")
o.bind("ALT + SHIFT + TAB", "Switch windows backward", "omarchy-shell window cyclePrev")
o.bind("ALT + Alt_L", "Commit window switch", "omarchy-shell window commitCycle", { release = true })

o.bind("PRINT", "Screenshot", "omarchy-capture-screenshot")
o.bind("ALT + PRINT", "Screenrecording", "omarchy-capture-screenrecording --stop-recording || omarchy-capture-screenrecording")
o.bind("SUPER + PRINT", "Color picker", "pkill hyprpicker || hyprpicker -a")

o.bind("XF86PowerOff", "Power", "omarchy-shell shell toggle omarchy.power", { locked = true })
o.bind("switch:on:Lid Switch", nil, "omarchy-system-lid-close", { locked = true })
o.bind("switch:off:Lid Switch", nil, "omarchy-hyprland-monitor-clamshell", { locked = true })

o.bind("SUPER + mouse:272", "Move window", hl.dsp.window.drag(), { mouse = true })
o.bind("SUPER + mouse:273", "Resize window", hl.dsp.window.resize(), { mouse = true })
