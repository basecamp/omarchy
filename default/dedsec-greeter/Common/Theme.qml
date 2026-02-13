pragma Singleton

import QtQuick
import Quickshell

Singleton {

    // SECTION Primitives

    readonly property color gray50: "#ffffff"
    readonly property color gray100: "#CACACA"
    readonly property color gray200: "#D9D9D9"
    readonly property color gray300: "#c3c3c3"
    readonly property color gray500: "#7a7a7a"
    readonly property color gray800: "#050A0E"

    readonly property color accentGreen: "#00FF41"
    readonly property color accentRed: "#fc3e38"

    // SECTION Theme

    readonly property color background: gray800

    readonly property color dedsecGray: gray200

    readonly property color textPrimary: gray50
    readonly property color textPrimaryDim: gray100
    readonly property color textPrimaryDimmer: gray300

    readonly property color textSecondary: gray500
    readonly property color secondary: gray500

    readonly property color textAccent: accentGreen

    readonly property color success: accentGreen
    readonly property color error: accentRed

    // SECTION Fonts

    property string fontFamily: "JetBrainsMono Nerd Font"
}
