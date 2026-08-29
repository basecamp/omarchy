import QtQuick
Item { property string title: ""; property string subtitle: ""; property string meta: ""; property real metaOpacity: 1; property Component iconComponent; implicitHeight: 72; Loader { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; sourceComponent: iconComponent }; Text { anchors.centerIn: parent; text: title; color: Color.foreground; font.bold: true } }
