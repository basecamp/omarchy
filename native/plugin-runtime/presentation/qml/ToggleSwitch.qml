import QtQuick
Rectangle { property bool checked: false; implicitWidth: 34; implicitHeight: 18; radius: 9; color: checked ? "#65d7a1" : "#354052"; Rectangle { width: 14; height: 14; radius: 7; y: 2; x: checked ? 18 : 2; color: "white" } }
