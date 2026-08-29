import QtQuick
Rectangle { property bool hasCursor: false; property color foreground: Color.foreground; color: hasCursor ? Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12) : "transparent"; radius: 6 }
