import QtQuick

Rectangle {
    property string title: ""
    property string message: ""
    property string confirmText: "Confirm"
    property bool opened: false

    signal confirmed()
    signal canceled()

    visible: opened
    color: "#e0151820"

    MouseArea {
        anchors.fill: parent
        onClicked: parent.canceled()
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - Style.space(32), Style.space(360))
        implicitHeight: content.implicitHeight + Style.space(32)
        height: implicitHeight
        radius: Style.space(10)
        color: "#202530"

        Column {
            id: content

            anchors.fill: parent
            anchors.margins: Style.space(16)
            spacing: Style.space(12)

            Text {
                width: parent.width
                visible: text !== ""
                text: title
                color: Color.foreground
                font.bold: true
                wrapMode: Text.Wrap
            }

            Text {
                width: parent.width
                text: message
                color: Color.foreground
                wrapMode: Text.Wrap
            }

            Row {
                anchors.right: parent.right
                spacing: Style.space(8)

                Button {
                    text: "Cancel"
                    onClicked: canceled()
                }

                Button {
                    text: confirmText
                    onClicked: confirmed()
                }

            }

        }

    }

}
