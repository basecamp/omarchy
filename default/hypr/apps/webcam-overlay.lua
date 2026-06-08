-- Webcam overlay window.
o.window({ title = "WebcamOverlay" }, {
  tag = "-default-opacity",
  float = true,
  pin = true,
  no_initial_focus = true,
  no_dim = true,
  opacity = "1 1",
  move = { "(monitor_w-window_w-40)", "(monitor_h-window_h-40)" },
})
