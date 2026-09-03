-- DaVinci Resolve window focus handling. Kept fully opaque: the default
-- translucency distorts colour-critical grading work.
o.window(".*[Rr]esolve.*", {
  float = true,
  stay_focused = true,
  -- Prevent modal dialog pointer warps when focus follows the mouse.
  no_follow_mouse = true,
  tag = "-default-opacity",
  opacity = "1 1",
})

o.window({ class = ".*[Rr]esolve.*", title = "^DaVinci Resolve( Studio)? - .+$" }, { fullscreen = true })
-- Resolve exposes the Voiceover panel under the generic "Dialog" title.
o.window({ class = ".*[Rr]esolve.*", title = "^(DaVinci Resolve( Studio)? - .+|Project Manager|Preferences|Find Directory|Dialog)$" }, { stay_focused = false })
