pragma Singleton
import QtQuick

QtObject {
  function wheelSteps(remainder, delta) {
    var total = remainder + delta
    var steps = total > 0 ? Math.floor(total / 120) : Math.ceil(total / 120)
    return ({steps: steps, remainder: total - steps * 120})
  }
}
