// How far the charge has to climb back above the threshold before another
// warning is armed. A bare `level > threshold` test re-arms on the rounding
// wobble at the boundary, so a battery hovering at the threshold warns over
// and over.
var LOW_BATTERY_REARM_MARGIN = 5

function batteryPercentage(device) {
  if (!device || !device.isPresent) return -1
  return Math.round(Number(device.percentage || 0) * 100)
}

function isDischarging(device, onBattery, dischargingState) {
  return !!(device && device.isPresent && onBattery && device.state === dischargingState)
}

// The warning is a critical toast, so it never expires on its own: something
// has to take it down once the battery is no longer in trouble. That makes
// this a three-way decision rather than a "should I warn" test — warn, clear
// the standing warning, or leave things as they are.
//
// staleWarningSwept covers the one warning nothing remembers: a critical toast
// is restored from disk when the shell process restarts, but the latch that
// knows it was sent is in-process only. Restart with the charger already in
// and the restored toast would stand forever, so the first real reading of a
// process clears it once, whether or not this process warned.
function lowBatteryWarningState(device, onBattery, dischargingState, threshold, alreadyNotified, staleWarningSwept) {
  var level = batteryPercentage(device)

  // No battery to read: a machine without one, or the display device before
  // UPower has populated it early in startup. Not a reading, so it does not
  // count as the sweep — that would spend the sweep before the battery is
  // even visible, and every tick on a desktop.
  if (level < 0) return { level: level, notify: false, dismiss: !!alreadyNotified, notifiedLowBattery: false, staleWarningSwept: !!staleWarningSwept }

  var recovered = !isDischarging(device, onBattery, dischargingState) || level > threshold + LOW_BATTERY_REARM_MARGIN

  if (recovered) return { level: level, notify: false, dismiss: !!alreadyNotified || !staleWarningSwept, notifiedLowBattery: false, staleWarningSwept: true }
  // Still low enough to be worth a warning, so a restored toast is left where
  // it is: it is telling the truth, and the warning below takes it down and
  // replaces it as soon as the charge crosses the threshold.
  if (level > threshold) return { level: level, notify: false, dismiss: false, notifiedLowBattery: !!alreadyNotified, staleWarningSwept: true }
  return { level: level, notify: !alreadyNotified, dismiss: false, notifiedLowBattery: true, staleWarningSwept: true }
}

if (typeof module !== "undefined") {
  module.exports = {
    batteryPercentage: batteryPercentage,
    isDischarging: isDischarging,
    lowBatteryWarningState: lowBatteryWarningState
  }
}
