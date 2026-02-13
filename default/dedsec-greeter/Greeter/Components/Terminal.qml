pragma ComponentBehavior: Bound
import QtQuick

import "../Services"
import "../Common"
import "../Config"

Column {
    id: terminal

    property int margins: 10

    property int fontSize: 14 * Units.vh

    property int maxLines: {
        const totalSpace = Screen.height * 0.25;
        const takenSpace = version.height + terminal.spacing;

        const availableLines = (totalSpace - takenSpace) / lineHeight;
        return Utils.clamp(Math.floor(availableLines), 0, 10);
    }

    property int lineHeight: textMetrics.height + 5 * Units.vh
    property alias rem: textMetrics.width

    readonly property font font: Qt.font({
        family: Settings.fontFamily,
        pixelSize: terminal.fontSize
    })

    required property var logModel

    spacing: 8 * Units.vh

    TextMetrics {
        id: textMetrics
        font: terminal.font
        text: "-"
    }

    ListView {
        id: logView

        model: terminal.logModel
        clip: true

        anchors {
            left: parent.left
            right: parent.right
        }

        height: terminal.lineHeight * terminal.maxLines

        boundsBehavior: Flickable.StopAtBounds
        interactive: false
        verticalLayoutDirection: ListView.TopToBottom

        Behavior on contentY {
            NumberAnimation {
                duration: 50
                easing.type: Easing.OutCubic
            }
        }

        header: Item {
            id: headerItem
            width: logView.width
            height: logView.height
        }

        delegate: Item {
            width: logView.width
            height: entry.implicitHeight

            required property string message

            Text {
                id: entry

                color: Theme.textPrimaryDimmer
                font: terminal.font

                lineHeight: terminal.lineHeight
                lineHeightMode: Text.FixedHeight
                wrapMode: Text.Wrap

                width: logView.width

                text: {
                    if (parent.message.startsWith("---")) {
                        const stripped = parent.message.replace(/-/g, "");

                        const spareRoom = Math.floor(terminal.width / textMetrics.advanceWidth) - 4 - (stripped.length);

                        const hyphenCount = Math.floor(spareRoom / 2);

                        return `${("-").repeat(hyphenCount)}  ${stripped}  ${("-").repeat(hyphenCount)}`;
                    }

                    return `» ${parent.message}`;
                }

                onImplicitHeightChanged: {
                    logView.contentY += implicitHeight;
                }
            }
        }

        Component.onCompleted: {
            TerminalManager.notifyReady();
        }
    }

    Accents {
        id: accents

        opacityDuration: 200
        translateDuration: 300

        anchors {
            left: parent.left
            right: parent.right
        }

        height: versionBorder.height

        SequentialAnimation {
            id: accentAnimation

            PauseAnimation {
                duration: 200
            }
            ScriptAction {
                script: accents.start()
            }
        }

        Component.onCompleted: {
            accentAnimation.start();
        }

        Rectangle {
            id: versionBorder

            color: "transparent"

            height: Math.round(version.height + 8)

            anchors {
                left: parent.left
                right: parent.right
            }

            border {
                color: Qt.darker(Theme.textPrimary, 1.6)
                width: 1
            }

            Text {
                id: version
                color: Qt.darker(Theme.textPrimary, 1.2)

                anchors {
                    verticalCenter: parent.verticalCenter
                    left: parent.left
                    leftMargin: 10
                }

                font {
                    pixelSize: 13 * Units.vh
                    family: Settings.fontFamily
                }

                text: "dedsec-krn-1.0 <> DedSecOS"
            }
        }
    }
}
