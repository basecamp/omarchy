import QtQuick

QtObject {
  property bool waitForEnd: false
  property string text: ""
  signal streamFinished()
}
