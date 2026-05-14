require("default.hypr.bindings.media")
require("default.hypr.bindings.clipboard")
require("default.hypr.bindings.tiling-v2")
require("default.hypr.bindings.utilities")

-- Application bindings without Omarchy's preinstalled web apps, TUIs, or desktop apps.
o.bind("SUPER + RETURN", "Terminal", "omarchy-launch-terminal")
o.bind("SUPER + SHIFT + RETURN", "Browser", "omarchy-launch-browser")
o.bind("SUPER + SHIFT + F", "File manager", o.launch("nautilus --new-window"))
o.bind("SUPER + ALT + SHIFT + F", "File manager (cwd)", "omarchy-launch-nautilus-cwd")
o.bind("SUPER + SHIFT + B", "Browser", "omarchy-launch-browser")
o.bind("SUPER + SHIFT + ALT + B", "Browser (private)", "omarchy-launch-browser --private")
o.bind("SUPER + SHIFT + N", "Editor", "omarchy-launch-editor")
