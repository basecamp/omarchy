import QtQuick

Rectangle {
    property string iconText: ""
    property string tooltipText: ""
    property string fontFamily: Style.font.family
    property color foreground: Color.foreground
    property bool bordered: false

    signal clicked()

    implicitWidth: 32
    implicitHeight: 32
    radius: 6
    color: mouseArea.containsMouse ? Color.alpha(foreground, 0.12) : "transparent"
    border.width: bordered ? 1 : 0
    border.color: Color.alpha(foreground, 0.25)

    Text {
        anchors.centerIn: parent
        text: parent.iconText
        color: parent.foreground
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
