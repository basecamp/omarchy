-- Keep the Windows VM display opaque instead of applying the default window opacity.
o.window({ class = "^xfreerdp$", title = "^Windows VM - Omarchy$" }, {
  tag = "-default-opacity",
  opacity = "1 1",
})
