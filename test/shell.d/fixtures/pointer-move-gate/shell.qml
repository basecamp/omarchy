import QtQuick
import Quickshell
import qs.Ui

ShellRoot {
  id: root

  function fail(message) {
    console.log("RESULT fail " + message)
    Qt.quit()
  }

  function runChecks() {
    if (gate.moved(row, { x: 2, y: 3 })) {
      fail("the default initial sample was accepted")
      return
    }
    if (gate.moved(row, { x: 3, y: 4 })) {
      fail("threshold-sized jitter was accepted")
      return
    }
    if (!gate.moved(row, { x: 5, y: 4 })) {
      fail("real pointer movement was ignored")
      return
    }

    gate.reset()
    if (gate.moved(row, { x: 7, y: 8 })) {
      fail("reset accepted its initial sample")
      return
    }
    if (gate.moved(row, { x: 7.6, y: 8 })) {
      fail("sub-threshold movement was accepted too early")
      return
    }
    if (!gate.moved(row, { x: 8.2, y: 8 })) {
      fail("slow cumulative movement was ignored")
      return
    }

    gate.allowInitialSample()
    if (!gate.moved(row, { x: 9, y: 10 })) {
      fail("the explicitly allowed initial sample was ignored")
      return
    }
    if (gate.moved(row, { x: 9, y: 10 })) {
      fail("the initial sample exception was not consumed")
      return
    }

    console.log("RESULT pass")
    Qt.quit()
  }

  Component.onCompleted: Qt.callLater(runChecks)

  Item {
    id: card
    width: 200
    height: 200

    Item {
      id: row
      x: 20
      y: 30
      width: 100
      height: 40
    }
  }

  PointerMoveGate {
    id: gate
    referenceItem: card
  }
}
