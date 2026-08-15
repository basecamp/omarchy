-- DaVinci Resolve window focus handling. Kept fully opaque: the default
-- translucency distorts colour-critical grading work.
o.window(".*[Rr]esolve.*", {
  float = true,
  stay_focused = true,
  no_follow_mouse = true,
  tag = "-default-opacity",
  opacity = "1 1",
})

o.window({ class = ".*[Rr]esolve.*", title = "^DaVinci Resolve( Studio)? - .+$" }, { fullscreen = true })
o.window({ class = ".*[Rr]esolve.*", title = "^(DaVinci Resolve( Studio)? - .+|Project Manager|Preferences|Find Directory)$" }, { stay_focused = false })
