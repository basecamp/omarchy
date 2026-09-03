import QtQml

QtObject {
  id: root

  enum Precision {
    Hours,
    Minutes,
    Seconds
  }

  property bool enabled: true
  property int precision: SystemClock.Seconds
  readonly property date date: internal.currentDate
  readonly property int hours: date.getHours()
  readonly property int minutes: date.getMinutes()
  readonly property int seconds: date.getSeconds()

  property QtObject _internal: QtObject {
    id: internal
    property date currentDate: new Date()
  }

  property Timer _timer: Timer {
    // Wake on the next requested wall-clock boundary rather than an interval
    // measured from object construction. This keeps minute/hour clocks honest
    // across delayed construction and scheduler jitter.
    interval: {
      const now = internal.currentDate
      const elapsed = root.precision === SystemClock.Hours
        ? now.getMinutes() * 60000 + now.getSeconds() * 1000 + now.getMilliseconds()
        : root.precision === SystemClock.Minutes
          ? now.getSeconds() * 1000 + now.getMilliseconds()
          : now.getMilliseconds()
      const period = root.precision === SystemClock.Hours ? 3600000
        : root.precision === SystemClock.Minutes ? 60000 : 1000
      return Math.max(1, period - elapsed)
    }
    repeat: true
    running: root.enabled
    onTriggered: internal.currentDate = new Date()
  }
}
