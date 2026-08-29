import QtQuick
FocusScope {
  signal moveRequested(int dx, int dy); signal activateRequested(); signal closeRequested(); signal tabRequested(int direction); signal textKey(string text)
  Keys.onPressed: event => { if (event.key === Qt.Key_Escape) closeRequested(); else if (event.key === Qt.Key_Return) activateRequested(); else if (event.text !== "") textKey(event.text) }
}
