pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import "../Common"

Item {
    id: root

    property color color: Theme.dedsecGray
    property int length: 10
    property real thickness: 1

    property int count: 0

    default property alias content: contentArea.data

    onCountChanged: {
        if (count > 4 || count < 0) {
            throw new Error(`CornerFrame.count: must be between 0 - 4, received: ${count}`);
        }
    }

    component CornerFrameImage: Image {
        source: "../Resources/corner-frame.svg"
        antialiasing: false
        smooth: false
    }

    component CornerSquareImage: Image {
        source: "../Resources/corner-square.svg"
        antialiasing: false
        smooth: false
    }

    Item {
        id: contentArea
        anchors.fill: parent

        // SECTION Top Left
        CornerFrameImage {
            anchors {
                top: contentArea.top
                left: contentArea.left
            }
        }
        Loader {
            active: root.count >= 3

            anchors {
                top: contentArea.top
                left: contentArea.left
            }
            sourceComponent: CornerSquareImage {}
        }

        // SECTION Top Right
        CornerFrameImage {
            anchors {
                right: contentArea.right
                top: contentArea.top
            }
            rotation: 90
        }
        Loader {
            active: root.count >= 4
            anchors {
                top: contentArea.top
                right: contentArea.right
            }

            sourceComponent: CornerSquareImage {}
        }

        // SECTION Bottom Right
        CornerFrameImage {
            anchors {
                bottom: contentArea.bottom
                right: contentArea.right
            }
            rotation: 180
        }
        Loader {
            active: root.count >= 2
            anchors {
                bottom: contentArea.bottom
                right: contentArea.right
            }

            sourceComponent: CornerSquareImage {}
        }

        // SECTION Bottom Left
        CornerFrameImage {
            anchors {
                bottom: contentArea.bottom
                left: contentArea.left
            }
            rotation: 270
        }
        Loader {
            active: root.count >= 1
            anchors {
                bottom: contentArea.bottom
                left: contentArea.left
            }

            sourceComponent: CornerSquareImage {}
        }
    }
}
