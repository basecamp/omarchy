-- zbarcam supplies the live preview for the network panel's one-shot QR scan.
o.window("^zbar$", {
  tag = "-default-opacity",
  float = true,
  center = true,
  pin = true,
  no_initial_focus = true,
  size = { 640, 480 },
  keep_aspect_ratio = true,
  opacity = "1 1",
})
