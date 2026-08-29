import QtQuick
import QtQml

Item {
    id: root
    width: 520
    height: 260

    readonly property string surfaceRole: "panel"
    readonly property bool acceptsKeyboardFocus: false
    readonly property int maximumFramesPerSecond: 15
    property var inputRegions: []
    property var writeCall: null
    property var readCall: null
    property string phase: "STARTING"
    property string detail: "Waiting for authenticated broker"

    function begin() {
        phase = "WRITING"
        detail = "storage.private/write requested"
        writeCall = runtime.invoke("storage_write", {
            key: "live-evidence",
            value: "broker-round-trip",
            quotaBytes: 65536,
            itemBytes: 4096
        })
        if (writeCall && writeCall.finished)
            finishWrite()
    }

    function finishWrite() {
        if (!writeCall.ok) {
            phase = "DENIED"
            detail = "write: " + writeCall.error
            return
        }
        phase = "READING"
        detail = "write allowed; storage.private/read requested"
        readCall = runtime.invoke("storage_read", {
            key: "live-evidence",
            quotaBytes: 65536,
            itemBytes: 4096
        })
        if (readCall && readCall.finished)
            finishRead()
    }

    function finishRead() {
        if (!readCall.ok) {
            phase = "FAILED"
            detail = "read: " + readCall.error
            return
        }
        phase = "AUTHORIZED"
        detail = "write + read completed; encoded result bytes: " + readCall.value.length
    }

    Component.onCompleted: begin()

    Connections {
        target: root.writeCall
        function onFinishedChanged() {
            if (root.writeCall.finished)
                root.finishWrite()
        }
    }

    Connections {
        target: root.readCall
        function onFinishedChanged() {
            if (root.readCall.finished)
                root.finishRead()
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#10151c"
        border.color: root.phase === "AUTHORIZED" ? "#54d68c" : "#6f8094"
        border.width: 3
        radius: 18

        Column {
            anchors.centerIn: parent
            width: parent.width - 64
            spacing: 18

            Text {
                width: parent.width
                text: "LIVE CAPABILITY PROOF"
                color: "#8ea1b5"
                font.pixelSize: 14
                font.bold: true
                font.letterSpacing: 2
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width
                text: root.phase
                color: root.phase === "AUTHORIZED" ? "#54d68c" : "#f5f7fa"
                font.pixelSize: 34
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width
                text: root.detail
                color: "#c6d0dc"
                font.pixelSize: 15
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
