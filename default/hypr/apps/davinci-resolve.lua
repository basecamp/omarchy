-- DaVinci Resolve window focus handling. Kept fully opaque: the default
-- translucency distorts colour-critical grading work.
o.window(".*[Rr]esolve.*", {
  float = true,
  stay_focused = true,
  tag = "-default-opacity",
  opacity = "1 1",
})

-- Resolve's floating main window ignores the bar's reserved zone, so the bar
-- covers its menu bar; fullscreen renders above top-layer surfaces. Scoped by
-- title so the splash and Project Manager keep their natural size.
o.window({ class = ".*[Rr]esolve.*", title = "^DaVinci Resolve - .+$" }, { fullscreen = true })
