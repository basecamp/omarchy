import QtQuick
Rectangle {
  property bool checked: false; property bool busy: false; property bool hasCursor: false; property color foreground: Color.foreground
  signal toggled()
  implicitWidth: 34; implicitHeight: 18; radius: 9; color: checked ? "#65d7a1" : "#354052"
  Rectangle { width: 14; height: 14; radius: 7; y: 2; x: parent.checked ? 18 : 2; color: "white" }
  MouseArea { anchors.fill: parent; enabled: !parent.busy; onClicked: parent.toggled() }
}
