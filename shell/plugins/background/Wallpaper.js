// Selection uses the surface's effective dimensions, after rotation and scaling.
function select(config, name, width, height, home) {
  if (!config || typeof config !== "object" || Array.isArray(config)) return ""
  var monitors = config.monitors
  var value = monitors && Object.prototype.hasOwnProperty.call(monitors, name)
    ? monitors[name] : config[height > width ? "portrait" : "landscape"]
  if (typeof value !== "string") return ""
  if (value.indexOf("~/") === 0) value = home + value.slice(1)
  return value.charAt(0) === "/" ? value : ""
}
