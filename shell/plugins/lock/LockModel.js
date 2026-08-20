function secondsFromConfig(value, fallback) {
  var n = Number(value)
  if (!isFinite(n) || n < 0) return fallback
  return Math.floor(n)
}

if (typeof module !== "undefined") {
  module.exports = {
    secondsFromConfig: secondsFromConfig
  }
}
