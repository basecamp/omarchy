pragma Translator: "KStandardActions"

import QtQuick
import Quickshell
import Omarchy.I18n

ShellRoot {
    readonly property string catalogPath: "/usr/share/locale/ja/LC_MESSAGES/kconfig6_qt.qm"
    readonly property string translatedText: qsTr("&Close")
    property int exitCode: 0
    property string sourceText

    Timer {
        id: verifyTimer
        interval: 1
        onTriggered: {
            if (translatedText === sourceText) {
                console.error(`TEST_FAIL: bound translation unchanged: ${translatedText}`)
                exitCode = 1
            } else {
                console.log(`TEST_PASS: ${sourceText} -> ${translatedText}`)
            }

            exitTimer.start()
        }
    }

    Timer {
        id: exitTimer
        interval: 1
        onTriggered: Qt.exit(exitCode)
    }

    Component.onCompleted: {
        Qt.uiLanguage = "en"
        sourceText = translatedText

        if (!Translator.load(catalogPath)) {
            console.error("TEST_FAIL: catalog did not load")
            exitCode = 1
            exitTimer.start()
            return
        }

        Qt.uiLanguage = "ja"
        verifyTimer.start()
    }
}
