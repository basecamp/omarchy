pragma ComponentBehavior: Bound

import QtQuick

import "../Common"

Grid {
    id: root
    columns: 3
    rows: 3
    spacing: 3

    property int size: 5
    property int delay: 100
    property bool active: true
    property color activeColor: Theme.background

    opacity: active ? 1 : 0

    component LoaderSquare: Rectangle {
        width: root.size
        height: root.size
        color: root.activeColor
        opacity: 0
    }

    // using coordinates system

    LoaderSquare {
        id: sq0_0
    }
    LoaderSquare {
        id: sq1_0
    }
    LoaderSquare {
        id: sq2_0
    }

    LoaderSquare {
        id: sq0_1
    }
    Rectangle {
        id: sq1_1
        width: root.size
        height: root.size
        color: "transparent"
    }
    LoaderSquare {
        id: sq2_1
    }

    LoaderSquare {
        id: sq0_2
    }
    LoaderSquare {
        id: sq1_2
    }
    LoaderSquare {
        id: sq2_2
    }

    SequentialAnimation {
        running: root.active
        loops: Animation.Infinite

        ParallelAnimation {
            NumberAnimation {
                target: sq0_0
                property: "opacity"
                to: 1
                duration: root.delay
            }
            NumberAnimation {
                target: sq0_1
                property: "opacity"
                from: 1
                to: 0
                duration: root.delay
            }
        }

        ParallelAnimation {
            NumberAnimation {
                target: sq0_0
                property: "opacity"
                to: 0
                duration: root.delay
            }
            NumberAnimation {
                target: sq1_0
                property: "opacity"
                to: 1
                duration: root.delay
            }
        }

        ParallelAnimation {
            NumberAnimation {
                target: sq1_0
                property: "opacity"
                to: 0
                duration: root.delay
            }
            NumberAnimation {
                target: sq2_0
                property: "opacity"
                to: 1
                duration: root.delay
            }
        }

        ParallelAnimation {
            NumberAnimation {
                target: sq2_0
                property: "opacity"
                to: 0
                duration: root.delay
            }
            NumberAnimation {
                target: sq2_1
                property: "opacity"
                to: 1
                duration: root.delay
            }
        }

        ParallelAnimation {
            NumberAnimation {
                target: sq2_1
                property: "opacity"
                to: 0
                duration: root.delay
            }
            NumberAnimation {
                target: sq2_2
                property: "opacity"
                to: 1
                duration: root.delay
            }
        }

        ParallelAnimation {
            NumberAnimation {
                target: sq2_2
                property: "opacity"
                to: 0
                duration: root.delay
            }
            NumberAnimation {
                target: sq1_2
                property: "opacity"
                to: 1
                duration: root.delay
            }
        }

        ParallelAnimation {
            NumberAnimation {
                target: sq1_2
                property: "opacity"
                to: 0
                duration: root.delay
            }
            NumberAnimation {
                target: sq0_2
                property: "opacity"
                to: 1
                duration: root.delay
            }
        }

        ParallelAnimation {
            NumberAnimation {
                target: sq0_2
                property: "opacity"
                to: 0
                duration: root.delay
            }
            NumberAnimation {
                target: sq0_1
                property: "opacity"
                to: 1
                duration: root.delay
            }
        }
    }
}
