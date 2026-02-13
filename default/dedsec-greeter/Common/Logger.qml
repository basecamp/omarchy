import QtQuick
import Quickshell

// TODO log bug report hot-reload + enums = crash when using Qt.enumValueToString

Item {
    id: logger

    required property string name

    property int level: Logger.Level.Debug
    property bool writeToFile: Quickshell.env("DEDSEC_DEBUG") === "1"
    property string filePath: "/tmp/dedsec.log"

    enum Level {
        Debug,
        Info,
        Warn,
        Error
    }

    readonly property var labels: ["debug", "info", "warn", "error"]
    readonly property var labelsShort: ["DBG", "INF", "WRN", "ERR"]

    function debug(message) {
        _log(Logger.Level.Debug, message);
    }

    function info(message) {
        _log(Logger.Level.Info, message);
    }

    function warn(message) {
        _log(Logger.Level.Warn, message);
    }

    function error(message) {
        _log(Logger.Level.Error, message);
    }

    function critical(message) {
        _log(Logger.Level.Error, `[CRITICAL] ${message}`);
        quitTimer.start();
    }

    Timer {
        id: quitTimer
        interval: 1000
        onTriggered: {
            console.error("[CRITICAL] check log for errors.");
            Qt.quit();
        }
    }

    function _log(level, message) {
        if (level < logger.level) {
            return;
        }

        const date = new Date();
        const timestamp = Utils.getTimestamp();

        const levelShort = logger.labelsShort[level];

        const consoleLogString = `[${timestamp}][${logger.name}] ${message}`;
        const fileLogString = `[${timestamp} ${levelShort}][${logger.name}] ${message}`;

        const method = logger.labels[level];
        console[method](consoleLogString);

        if (logger.writeToFile) {
            Quickshell.execDetached(["sh", "-c", `echo "${fileLogString}" >> ${logger.filePath}`]);
        }
    }
}
