pragma Singleton
import QtQuick
import "WallclockMath.js" as Detect

// Notices when wall-clock time is stepped rather than advanced, so anything
// displaying a clock can re-read it.
//
// Timers are scheduled as a delay measured on CLOCK_MONOTONIC, which stops
// while the machine is suspended. Quickshell's SystemClock schedules its next
// tick as the delay to the top of the next minute, so a clock that had four
// seconds left to run when the lid closed still has four seconds left when it
// opens — and reports the pre-suspend time until they elapse. The length of
// the sleep does not matter: an eight-hour suspend and a ten-second one leave
// the same remainder to burn down. Most of that minute passes behind the lock
// screen; what is left of it lands on the bar the user unlocks into.
//
// An NTP correction after a long time offline steps the clock the same way
// and leaves the same gap. A timezone change does not — it moves the offset,
// not the epoch, and omarchy-menu-timezone already refreshes the clock over
// IPC when it changes one.
//
// Checking the wall clock when a timer fires is the cheaper move, and it is
// the one the lock service makes before blanking a freshly woken screen: a
// countdown that spanned a suspend is discarded and re-armed, at the cost of
// no extra wakeups at all. SystemClock already does the same thing — setTime
// and schedule both fall back to the current time when the tick they were
// waiting for turns out to be more than 500ms stale — and that is precisely
// why the clock rights itself a minute after waking rather than staying
// wrong. It cannot do better, because the check only runs when the late tick
// finally arrives, and waiting for that tick is the whole bug.
//
// So the check has to run on a schedule of its own. Nothing else will raise
// it: logind announces a resume on the system bus, but the shell has no
// D-Bus of its own, and a clock stepped by NTP announces nothing anywhere.
QtObject {
  id: root

  readonly property int interval: 1000

  // A tick can run late under load without the clock having moved, so the
  // threshold clears ordinary scheduling jitter by a wide margin while
  // staying far below the shortest step worth reacting to.
  readonly property int threshold: 3000

  signal jumped(real deltaMs)

  property real lastTick: Date.now()

  // Re-reads the wall clock and reschedules the next tick from now. Toggling
  // `enabled` is what forces it: SystemClock recomputes both the time it
  // reports and the delay it waits on when it is re-enabled, and exposes no
  // other way to ask for either.
  function resync(clock) {
    clock.enabled = false
    clock.enabled = true
  }

  property Timer watchdog: Timer {
    interval: root.interval
    running: true
    repeat: true

    onTriggered: {
      var now = Date.now()
      var elapsed = now - root.lastTick
      root.lastTick = now

      if (Detect.isDiscontinuity(elapsed, root.interval, root.threshold)) root.jumped(elapsed)
    }
  }
}
