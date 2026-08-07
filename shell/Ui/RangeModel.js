function thresholdEnabled(minimum, maximum, threshold) {
  return isFinite(threshold) && threshold > minimum && threshold < maximum
}

function fraction(value, minimum, maximum) {
  var range = maximum - minimum
  if (range <= 0) return 0
  return Math.max(0, Math.min(1, (value - minimum) / range))
}

function amplified(value, minimum, maximum, threshold) {
  return thresholdEnabled(minimum, maximum, threshold) && value > threshold
}

if (typeof module !== "undefined") {
  module.exports = {
    thresholdEnabled: thresholdEnabled,
    fraction: fraction,
    amplified: amplified
  }
}
