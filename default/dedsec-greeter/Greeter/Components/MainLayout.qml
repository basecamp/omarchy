import QtQuick
import QtQuick.Layouts

import "../Services"
import "../Components"
import "../Config"
import "../Common"

Item {
    id: root

    anchors.fill: parent

    focus: true

    Keys.onPressed: event => {
        // Disable Ctrl + C exiting
        if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
            event.accepted = true;
        }

        // Confirmation prompt
        if ((event.key === Qt.Key_Enter || event.key === Qt.Key_Return) && AuthManager.state === AuthManager.State.Success) {
            root.confirmed = true;
            exitAnimation.resume();
            event.accepted = true;
        }

        if (Settings.isDebug) {
            switch (event.key) {
            case Qt.Key_F12:
                AuthManager.state = AuthManager.State.Success;
                break;
            case Qt.Key_Escape:
                Qt.quit();
                break;
            }
        }
    }

    Image {
        id: backgroundImage
        anchors.fill: parent
        source: "../Resources/lock.png"
    }

    Splash {
        id: splash

        width: 21.2 * passwordField.rem
        height: 3.7 * passwordField.rem

        anchors {
            horizontalCenter: parent.horizontalCenter
            verticalCenter: root.top
            verticalCenterOffset: root.height * 0.406
        }
    }

    ColumnLayout {
        id: fieldGroup

        anchors {
            top: splash.bottom
            topMargin: 50 * Units.vh

            horizontalCenter: root.horizontalCenter
        }
        width: 21.2 * passwordField.rem

        transform: Translate {
            id: fieldGroupTranslate
        }

        spacing: 0
        RowLayout {
            id: user
            spacing: 5
            Image {
                Layout.preferredHeight: 10
                fillMode: Image.PreserveAspectCrop
                source: "../Resources/barcode.svg"
            }
            Text {
                id: userText
                color: Theme.textPrimary
                font {
                    pixelSize: 14
                    family: Settings.fontFamily
                }
                text: AuthManager.user.toUpperCase()
            }
        }

        PasswordField {
            id: passwordField
            Layout.fillWidth: true
            Layout.preferredHeight: 3.10 * passwordField.rem

            enabled: AuthManager.state === AuthManager.State.Ready
            color: {
                switch (AuthManager.state) {
                case AuthManager.State.Loading:
                    return Theme.textPrimaryDim;
                case AuthManager.State.Success:
                case AuthManager.State.Finish:
                    return Theme.success;
                case AuthManager.State.Failed:
                    return Theme.error;
                default:
                    return Theme.textPrimary;
                }
            }
            onAccepted: {
                AuthManager.respond(passwordField.text);
            }
            Component.onCompleted: {
                passwordField.forceActiveFocus();
            }
        }

        Rectangle {
            id: loginButton
            Layout.preferredHeight: 26
            Layout.preferredWidth: parent.width * 0.38
            Layout.alignment: Qt.AlignRight

            color: Theme.dedsecGray

            Text {
                text: "LOGIN"
                opacity: AuthManager.state === AuthManager.State.Loading ? 0 : 1

                anchors {
                    horizontalCenter: parent.horizontalCenter
                    verticalCenter: parent.verticalCenter
                }

                color: Theme.background

                font {
                    pixelSize: 16
                    family: Settings.fontFamily
                }
            }

            Spinner {
                active: AuthManager.state === AuthManager.State.Loading

                anchors {
                    horizontalCenter: loginButton.horizontalCenter
                    verticalCenter: loginButton.verticalCenter
                }
            }
        }
    }

    Disclaimer {
        id: disclaimer

        anchors {
            left: splash.left
            right: splash.right
            top: splash.bottom
            topMargin: 25 * Units.vh + 50 * Units.vh + fieldGroup.height + loginButton.height + 15 * Units.vh
            leftMargin: 2
        }
    }

    Time {
        id: time

        anchors {
            top: root.top
            left: root.left
            leftMargin: root.height * 0.05
            topMargin: root.height * 0.05
        }
    }

    Terminal {
        id: terminal
        logModel: TerminalManager.logModel
        anchors {
            bottom: parent.bottom
            left: parent.left
            // visual fix on border, subpixel gets smoothed
            leftMargin: Math.round(parent.width * 0.037)
            bottomMargin: Math.round(parent.height * 0.046)
        }
        width: 94.5 * terminal.rem
    }

    Typewriter {
        id: headerText
        initialText: "IDENTITY VERIFIED"

        anchors {
            bottom: splash.top
            bottomMargin: 20
            horizontalCenter: root.horizontalCenter
        }

        color: Theme.dedsecGray
        font {
            pixelSize: 24
            family: Settings.fontFamily
        }
        opacity: 0
    }

    property bool confirmed: false
    Text {
        id: confirmationText
        text: `[<span style="color: ${root.confirmed ? Theme.success : Theme.dedsecGray}">ENTER</span>] TO CONFIRM`
        anchors {
            top: splash.bottom
            topMargin: 30
            horizontalCenter: root.horizontalCenter
        }
        color: Theme.dedsecGray
        font {
            family: Settings.fontFamily
            pixelSize: 18
        }
        opacity: 0
        textFormat: Text.RichText
    }

    Status {
        id: status
        anchors {
            right: root.right
            top: root.top
            rightMargin: (root.height * 0.0375) - status.barWidth  // visual fix
            topMargin: root.height * 0.046
        }
    }

    DeviceId {
        id: device

        // height: root.height * 0.485
        height: root.height * 0.45

        anchors {
            right: root.right
            bottom: root.bottom

            rightMargin: root.height * 0.0375
            bottomMargin: root.height * 0.046
        }
    }

    IdentityCard {
        id: identityCard
        anchors.centerIn: parent
        height: 220
        width: 450
    }

    SequentialAnimation {
        id: startSplash
        running: Settings.animationProfile(Settings.AnimationMode.All)

        PropertyAction {
            target: disclaimer
            property: "opacity"
            value: 0
        }

        ScriptAction {
            script: startSplash.pause()
        }

        // prevents race where pause allows further instructions to be executed
        // if not time-based, e.g. splash.start()
        PauseAnimation {}

        ParallelAnimation {
            ScriptAction {
                script: splash.start()
            }

            NumberAnimation {
                target: disclaimer
                property: "opacity"
                to: 1
                duration: 100
                easing.type: Easing.InCubic
            }
        }
    }

    SequentialAnimation {
        id: startupAnimation
        running: Settings.animationProfile(Settings.AnimationMode.All)

        // SECTION Setup

        PropertyAction {
            target: splash
            property: "anchors.verticalCenterOffset"
            value: root.height / 2
        }
        PropertyAction {
            target: disclaimer
            property: "anchors.topMargin"
            value: 25 * Units.vh
        }
        PropertyAction {
            target: fieldGroup
            property: "opacity"
            value: 0
        }

        ScriptAction {
            script: startupAnimation.pause()
        }

        // SECTION Begin

        ParallelAnimation {
            id: slideApart

            NumberAnimation {
                target: splash
                property: "anchors.verticalCenterOffset"
                to: root.height * 0.406
                duration: 500
                easing.type: Easing.InOutCirc
            }

            NumberAnimation {
                target: disclaimer
                property: "anchors.topMargin"
                to: 25 * Units.vh + fieldGroup.anchors.topMargin + fieldGroup.height + loginButton.height + 15 * Units.vh
                duration: 500
                easing.type: Easing.InOutCirc
            }

            SequentialAnimation {
                PauseAnimation {
                    duration: 300
                }

                NumberAnimation {
                    target: fieldGroup
                    property: "opacity"
                    to: 1
                    duration: 200
                    easing.type: Easing.OutExpo
                }
            }
        }

        onFinished: TerminalManager.unPause()
    }

    ParallelAnimation {
        id: revealCard

        ScriptAction {
            script: identityCard.start()
        }

        NumberAnimation {
            target: headerText
            property: "opacity"
            to: 1
            duration: 200
        }

        NumberAnimation {
            target: confirmationText
            property: "opacity"
            to: 1
            duration: 200
        }

        ScriptAction {
            script: confirmationBreathing.start()
        }
    }

    SequentialAnimation {
        id: exitAnimation
        running: AuthManager.state === AuthManager.State.Success

        ScriptAction {
            script: disclaimer.exit()
        }

        PauseAnimation {
            duration: 200
        }

        ScriptAction {
            script: splash.startCard()
        }

        // SECTION move splash to centre, slide and fade fieldGroup

        ParallelAnimation {
            NumberAnimation {
                target: splash
                property: "anchors.verticalCenterOffset"
                to: root.height / 2
                duration: 500
                easing.type: Easing.InOutCirc
            }

            NumberAnimation {
                target: fieldGroup
                property: "anchors.topMargin"
                duration: 200
                to: -splash.height
            }

            NumberAnimation {
                target: fieldGroup
                property: "opacity"
                duration: 150
                to: 0
            }

            ScriptAction {
                // allow confirmation 'enter'
                script: root.forceActiveFocus()
            }
        }

        // SECTION card expansion from splash

        ParallelAnimation {
            NumberAnimation {
                target: splash
                property: "width"
                duration: 300
                to: identityCard.width + 40
            }

            NumberAnimation {
                target: splash
                property: "height"
                duration: 300
                to: identityCard.height + 40
            }
        }

        // SECTION awaiting confirmation

        ScriptAction {
            script: exitAnimation.pause()
        }

        // buffer pause
        PauseAnimation {}

        ScriptAction {
            script: headerText.overwrite("ENTERING SYSTEM")
        }

        ScriptAction {
            script: {
                confirmationBreathing.stop();
            }
        }

        NumberAnimation {
            target: confirmationText
            property: "opacity"
            to: 0
            duration: 200
            easing.type: Easing.InExpo
        }

        SequentialAnimation {
            id: exitToSession

            NumberAnimation {
                target: identityCard
                property: "opacity"
                to: 0
                duration: 200
            }

            ParallelAnimation {
                NumberAnimation {
                    target: splash
                    property: "width"
                    duration: 300
                    to: headerText.width
                }

                NumberAnimation {
                    target: splash
                    property: "height"
                    duration: 300
                    to: 5
                }
            }
        }

        PauseAnimation {
            duration: 200
        }

        SequentialAnimation {
            ScriptAction {
                script: splash.startFinal()
            }

            PauseAnimation {
                duration: 1200
            }
        }

        ScriptAction {
            script: AuthManager.finish()
        }
    }

    SequentialAnimation {
        id: confirmationBreathing

        loops: Animation.Infinite

        NumberAnimation {
            target: confirmationText
            property: "opacity"
            to: 0.80
            duration: 1500
        }
        NumberAnimation {
            target: confirmationText
            property: "opacity"
            to: 1
            duration: 1500
        }
    }

    Connections {
        target: TerminalManager

        function onPaused(marker: string) {
            if (Settings.animationProfile(Settings.AnimationMode.Reduced)) {
                // startup sequence won't run so manually unpause
                TerminalManager.unPause();
            }

            if (marker == "UI_INIT") {
                startSplash.resume();
            }
        }
    }

    Connections {
        target: splash

        function onProgressBarMidway() {
            time.start();
            device.start();
            status.start();
        }

        function onRevealFinished() {
            startupAnimation.resume();
        }

        function onCardFinished() {
            revealCard.start();
        }
    }
}
