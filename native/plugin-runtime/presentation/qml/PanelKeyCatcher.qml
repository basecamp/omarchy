import QtQuick

Item {
  property bool blocked: false
  signal moveRequested(int dx, int dy)
  signal activateRequested()
  signal closeRequested()
  signal tabRequested(int direction)
  signal textKey(string text)

  focus: true
  Keys.onPressed: function(event) {
    if (blocked) return
    if (event.key === Qt.Key_Up) moveRequested(0, -1)
    else if (event.key === Qt.Key_Down) moveRequested(0, 1)
    else if (event.key === Qt.Key_Left) moveRequested(-1, 0)
    else if (event.key === Qt.Key_Right) moveRequested(1, 0)
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) activateRequested()
    else if (event.key === Qt.Key_Escape) closeRequested()
    else if (event.key === Qt.Key_Tab) tabRequested(event.modifiers & Qt.ShiftModifier ? -1 : 1)
    else if (event.text !== "") textKey(event.text)
    else return
    event.accepted = true
  }
}
