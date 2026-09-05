import QtQuick

FocusScope {
  property bool blocked: false
  signal moveRequested(int dx, int dy)
  signal activateRequested()
  signal returnRequested()
  signal closeRequested()
  signal deleteRequested()
  signal tabRequested(int direction)
  signal textKey(string text)

  focus: true
  Keys.priority: Keys.BeforeItem
  Keys.onPressed: function(event) {
    if (blocked || event.isAutoRepeat) return
    if (event.key === Qt.Key_Escape) closeRequested()
    else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
      tabRequested((event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab ? -1 : 1)
    else if (event.key === Qt.Key_Down || event.text === "j") moveRequested(0, 1)
    else if (event.key === Qt.Key_Up || event.text === "k") moveRequested(0, -1)
    else if (event.key === Qt.Key_Right || event.text === "l") moveRequested(1, 0)
    else if (event.key === Qt.Key_Left || event.text === "h") moveRequested(-1, 0)
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      returnRequested()
      activateRequested()
    } else if (event.key === Qt.Key_Space) activateRequested()
    else if (event.text === "x" || event.text === "X") deleteRequested()
    else if (event.text !== "") textKey(event.text)
    else return
    event.accepted = true
  }
}
