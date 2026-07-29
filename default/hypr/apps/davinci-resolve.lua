-- DaVinci Resolve window focus handling. Kept fully opaque: the default
-- translucency distorts colour-critical grading work.
o.window(".*[Rr]esolve.*", {
  float = true,
  stay_focused = true,
  tag = "-default-opacity",
  opacity = "1 1",
})

-- stay_focused above stops Resolve's transient popups closing on mouse-out
-- (hyprwm/Hyprland#12235), but pinning the windows they open over makes two
-- windows fight for focus and traps the pointer. Unpin the parents only.
o.window({ class = ".*[Rr]esolve.*", title = "^(DaVinci Resolve - .+|Project Manager)$" }, { stay_focused = false })
