-- DaVinci Resolve window focus handling. Kept fully opaque: the default
-- translucency distorts colour-critical grading work.
o.window(".*[Rr]esolve.*", {
  float = true,
  -- Prevent modal dialog pointer warps when focus follows the mouse.
  no_follow_mouse = true,
  tag = "-default-opacity",
  opacity = "1 1",
})

-- Maximize rather than fullscreen: the bar still clears Resolve's menu, but
-- other windows on the workspace can be raised above it.
o.window({ class = ".*[Rr]esolve.*", title = "^DaVinci Resolve( Studio)? - .+$" }, { maximize = true })

-- Resolve is XWayland-only, so Hyprland honours the geometry its dialogs ask
-- for: undersized file pickers on HiDPI, off-screen on mixed-scale layouts.
o.window({ class = ".*[Rr]esolve.*", title = "^(Open|Save As|Find Directory|Project Media Location)$" }, { tag = "+floating-window" })
o.window({ class = ".*[Rr]esolve.*", title = "^Create New Project$" }, { center = true })
