-- Initial sizes mirror the live presets in omarchy-capture-webcam-resize.
o.window("^WebcamOverlay-small$", {
  size = { 240, 270 },
  move = { "(monitor_w-240-40)", "(monitor_h-270-40)" },
})
o.window("^WebcamOverlay-medium$", {
  size = { 360, 405 },
  move = { "(monitor_w-360-40)", "(monitor_h-405-40)" },
})
o.window("^WebcamOverlay-large$", {
  size = { 480, 540 },
  move = { "(monitor_w-480-40)", "(monitor_h-540-40)" },
})

-- The dedicated app id keeps this out of mpv's generic centered floating rules,
-- so the camera appears at its final corner position.
o.window({ class = "^WebcamOverlay-(small|medium|large)$", title = "^WebcamOverlay$" }, {
  tag = "-default-opacity",
  float = true,
  pin = true,
  no_initial_focus = true,
  no_dim = true,
  opacity = "1 1",
})
