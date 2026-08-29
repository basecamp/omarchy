import QtQuick

Rectangle {
    property string text: ""
    property string tooltipText: ""
    property string fontFamily: Style.font.family

    signal clicked()

    implicitWidth: Math.max(Style.space(72), label.implicitWidth + Style.space(24))
    implicitHeight: Style.space(32)
    radius: Style.space(6)
    color: enabled ? (mouseArea.containsMouse ? "#46536a" : "#354052") : "#252a34"

    Text {
        id: label

        anchors.centerIn: parent
        text: parent.text
        color: Color.foreground
        font.family: parent.fontFamily
    }

    MouseArea {
        id: mouseArea

        anchors.fill: parent
        hoverEnabled: true
        enabled: parent.enabled
        onClicked: parent.clicked()
    }

}
