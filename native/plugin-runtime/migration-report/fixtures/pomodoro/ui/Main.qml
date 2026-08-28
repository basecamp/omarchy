import QtQuick
import Quickshell.Io

Item {
    FileView { path: "/tmp/pomodoro-state.json" }
    Process { command: ["pw-play", "complete.wav"] }
    property string effect: "Notification"
}
