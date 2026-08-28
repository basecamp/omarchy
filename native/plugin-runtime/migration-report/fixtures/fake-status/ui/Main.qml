import QtQuick
import Quickshell.Io

Item {
    Process { command: ["basecamp", "status"] }
    function open(itemUrl) { Qt.openUrlExternally(itemUrl) }
}
