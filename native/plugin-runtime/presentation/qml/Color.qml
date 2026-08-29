import QtQuick
pragma Singleton

QtObject {
    readonly property color foreground: "#e7e9ee"
    readonly property color urgent: "#ef7d8b"
    readonly property color accent: "#65d7a1"
    readonly property QtObject
    popups: QtObject {
        readonly property color text: "#e7e9ee"
    }

    function alpha(value, opacity) {
        return Qt.rgba(value.r, value.g, value.b, opacity);
    }

}
