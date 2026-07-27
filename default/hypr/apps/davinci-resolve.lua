-- DaVinci Resolve window focus handling. Kept fully opaque: the default
-- translucency distorts colour-critical grading work.
o.window(".*[Rr]esolve.*", {
  float = true,
  stay_focused = true,
  tag = "-default-opacity",
  opacity = "1 1",
})
