import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui

Item {
  id: root

  property string backgroundPath: ""
  property int backgroundVersion: 0
  property bool fingerprintConfigured: false
  property bool authenticatingPassword: false
  property string failureMessage: ""
  property int failedAttempts: 0
  property bool inputEnabled: true
  property bool loadBackground: true
  property string passwordText: ""
  property bool syncingPasswordText: false
  property bool passwordRevealed: false

  readonly property string placeholderText: "Enter Password"
  readonly property int fieldWidth: 381
  readonly property int fieldHeight: 67
  readonly property int outlineThickness: 3
  readonly property int fieldFontSize: Math.round(Style.font.heading * 1.125)
  readonly property int passwordDotFontSize: Math.round(Style.font.heading * 1.33)
  readonly property int passwordDotLetterSpacing: Math.round(Style.font.heading * 0.19)
  // Space to keep clear on each side of the field for the fingerprint icon
  // (icon width plus a gap) so the centered dots never run under it.
  readonly property real fingerprintReserve: fingerprintConfigured ? Math.round(fingerprintIcon.implicitWidth + 12) : 0
  // Same idea, for the always-on reveal toggle.
  readonly property real eyeReserve: Math.round(eyeButton.width + 4)
  // Shrink the dots to fit once the password outgrows the field, so every
  // keystroke stays visible — otherwise long passwords clip with no feedback.
  readonly property real passwordDotScale: dotMetrics.advanceWidth > 0
    ? Math.min(1, (passwordInput.width - 4) / dotMetrics.advanceWidth)
    : 1
  // Same idea as passwordDotScale, but for the revealed plain-text password.
  readonly property real revealedTextScale: revealedMetrics.advanceWidth > 0
    ? Math.min(1, (passwordInput.width - 4) / revealedMetrics.advanceWidth)
    : 1
  readonly property bool showPasswordCursor: inputEnabled && !authenticatingPassword && failureMessage.length === 0
  readonly property bool errorState: failureMessage.length > 0
  readonly property var inputBorderSpec: errorState
    ? Border.surfaceSpec("lock", "border-error", Color.lock.borderError, root.outlineThickness, "border-alpha")
    : Border.surfaceSpec("lock", "border-active", Color.lock.borderActive, root.outlineThickness, "border-alpha")

  signal submitPassword(string password)
  signal passwordTextEdited(string password)
  signal clearFailureRequested()
  signal wakeRequested()

  // Cache-busts the lock background by appending `?v=`. Adding a query
  // string keeps Image's loader happy while forcing it to reload when the
  // user picks a new background mid-session.
  function fileUrl(path) {
    if (!path) return ""
    var encoded = String(path).split("/").map(encodeURIComponent).join("/")
    return "file://" + encoded + "?v=" + backgroundVersion
  }

  function forcePasswordFocus() {
    passwordInput.forceActiveFocus()
  }

  function clearPassword() {
    passwordTextEdited("")
  }

  // Shared by the mouse toggle and the Ctrl+Space shortcut. Guarded on
  // non-empty input so neither path can arm a reveal that then applies to
  // the next attempt's first keystrokes once the field re-fills.
  function toggleReveal() {
    if (passwordInput.text.length === 0) return
    passwordRevealed = !passwordRevealed
  }

  function syncPasswordText() {
    if (passwordInput.text === passwordText) return
    syncingPasswordText = true
    passwordInput.text = passwordText
    syncingPasswordText = false
  }

  onPasswordTextChanged: syncPasswordText()
  onInputEnabledChanged: {
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }
  Component.onCompleted: {
    syncPasswordText()
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }

  // Measures the masked password at full size; passwordDotScale compares this
  // against the field width to decide how far the dots must shrink to fit.
  TextMetrics {
    id: dotMetrics
    font.family: Style.font.family
    font.pixelSize: root.passwordDotFontSize
    font.letterSpacing: root.passwordDotLetterSpacing
    text: "●".repeat(passwordInput.text.length)
  }

  // Measures the revealed plain-text password; revealedTextScale compares
  // this against the field width to decide how far it must shrink to fit.
  TextMetrics {
    id: revealedMetrics
    font.family: Style.font.family
    font.pixelSize: root.fieldFontSize
    text: passwordInput.text
  }

  Rectangle {
    anchors.fill: parent
    color: Color.background

    Image {
      id: wallpaper
      anchors.fill: parent
      source: root.loadBackground ? root.fileUrl(root.backgroundPath) : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: false
      sourceSize.width: width
      sourceSize.height: height
    }

    MultiEffect {
      anchors.fill: wallpaper
      source: wallpaper
      autoPaddingEnabled: false
      blurEnabled: root.loadBackground && wallpaper.status === Image.Ready
      blur: 1.0
      blurMax: 128
      blurMultiplier: 1.25
      contrast: -0.08
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onClicked: { root.wakeRequested(); root.forcePasswordFocus() }
      onPositionChanged: root.wakeRequested()
    }

    BorderSurface {
      id: inputField
      width: root.fieldWidth
      height: root.fieldHeight
      anchors.centerIn: parent
      color: Color.lock.background
      borderSpec: root.inputBorderSpec
      radius: Style.cornerRadius
      clip: true

      TextInput {
        id: passwordInput
        anchors.fill: parent
        anchors.topMargin: inputField.borderTop
        // Reserve the icons' width on both sides so the centered dots stay
        // symmetric and never slide under them as the password grows.
        anchors.rightMargin: inputField.borderRight + 18 + root.fingerprintReserve + root.eyeReserve
        anchors.bottomMargin: inputField.borderBottom
        anchors.leftMargin: inputField.borderLeft + 18 + root.fingerprintReserve + root.eyeReserve
        verticalAlignment: TextInput.AlignVCenter
        horizontalAlignment: TextInput.AlignHCenter
        activeFocusOnPress: true
        clip: true
        enabled: root.inputEnabled && !root.authenticatingPassword
        readOnly: root.authenticatingPassword
        echoMode: root.passwordRevealed ? TextInput.Normal : TextInput.Password
        passwordCharacter: "\u25CF"
        passwordMaskDelay: 0
        color: Color.lock.text
        selectionColor: Color.lock.selection
        selectedTextColor: Color.lock.text
        font.family: Style.font.family
        font.pixelSize: {
          if (text.length === 0) return root.fieldFontSize
          return root.passwordRevealed
            ? Math.max(1, Math.floor(root.fieldFontSize * root.revealedTextScale))
            : Math.max(1, Math.floor(root.passwordDotFontSize * root.passwordDotScale))
        }
        font.letterSpacing: text.length > 0 && !root.passwordRevealed ? root.passwordDotLetterSpacing * root.passwordDotScale : 0
        cursorVisible: activeFocus && root.showPasswordCursor && text.length > 0
        cursorDelegate: Rectangle {
          width: 2
          color: Color.lock.text
          visible: passwordInput.cursorVisible
        }

        onTextChanged: {
          if (!root.syncingPasswordText) root.passwordTextEdited(text)
          if (text.length > 0) {
            root.wakeRequested()
          } else {
            // Don't leave the field armed to reveal next time someone starts typing.
            root.passwordRevealed = false
          }
          if (text.length > 0 && root.failureMessage.length > 0) root.clearFailureRequested()
        }

        onAccepted: {
          var submitted = root.passwordText
          root.passwordTextEdited("")
          if (submitted.length > 0) root.submitPassword(submitted)
        }

        Keys.onPressed: function(event) {
          root.wakeRequested()
          if (event.key === Qt.Key_Escape || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U)) {
            root.passwordTextEdited("")
            event.accepted = true
          } else if (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_Space) {
            // Ctrl+Space (not Alt-based, so it won't collide with AltGr
            // composition on non-US keyboard layouts) reveals the password
            // without touching the mouse.
            root.toggleReveal()
            event.accepted = true
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        anchors.fill: passwordInput
        text: root.authenticatingPassword ? "Checking…" : (root.failureMessage.length > 0 ? root.failureMessage : root.placeholderText)
        visible: passwordInput.text.length === 0
        color: root.authenticatingPassword ? Color.lock.text : (root.failureMessage.length > 0 ? Color.lock.textError : Color.lock.placeholder)
        font.family: Style.font.family
        font.pixelSize: root.fieldFontSize
        font.italic: !root.authenticatingPassword && root.failureMessage.length > 0
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
      }

      // Fingerprint hint pinned inside the field's right edge when a sensor is
      // enrolled, so the user knows they can touch to unlock instead of typing.
      // Matches hyprlock, which draws its fingerprint icon in the same spot.
      Text {
        id: fingerprintIcon
        objectName: "fingerprintIndicator"
        anchors.right: parent.right
        anchors.rightMargin: inputField.borderRight + 18
        anchors.verticalCenter: parent.verticalCenter
        visible: root.fingerprintConfigured
        text: "󰈷"
        color: Color.lock.placeholder
        font.family: Style.font.family
        font.pixelSize: Math.round(root.fieldFontSize * 1.1)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }

      // Eye toggle: click-and-hold-free reveal of the password. Sits just
      // inside the fingerprint icon (or in its spot, when no sensor is
      // enrolled) and never steals focus from the text field. Always shown
      // (dimmed while empty) so it's easy to spot before you start typing.
      Rectangle {
        id: eyeButton
        objectName: "passwordRevealToggle"
        width: eyeIcon.implicitWidth + 16
        height: eyeIcon.implicitHeight + 12
        radius: height / 2
        anchors.right: root.fingerprintConfigured ? fingerprintIcon.left : parent.right
        anchors.rightMargin: root.fingerprintConfigured ? 12 : inputField.borderRight + 12
        anchors.verticalCenter: parent.verticalCenter
        color: eyeArea.containsMouse ? Util.alpha(Color.lock.text, 0.12) : "transparent"

        Accessible.role: Accessible.Button
        Accessible.name: root.passwordRevealed ? "Hide password" : "Show password"
        Accessible.description: "Toggle whether the typed password is shown in plain text"
        Accessible.focusable: passwordInput.text.length > 0
        Accessible.onPressAction: root.toggleReveal()

        Text {
          id: eyeIcon
          anchors.centerIn: parent
          text: root.passwordRevealed ? "󰈉" : "󰈈"
          color: passwordInput.text.length > 0
            ? (root.passwordRevealed ? Color.lock.text : Util.alpha(Color.lock.text, 0.8))
            : Util.alpha(Color.lock.text, 0.35)
          font.family: Style.font.family
          font.pixelSize: Math.round(root.fieldFontSize * 1.1)
        }

        MouseArea {
          id: eyeArea
          objectName: "passwordRevealMouseArea"
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: passwordInput.text.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
          enabled: passwordInput.text.length > 0
          onClicked: {
            root.toggleReveal()
            root.forcePasswordFocus()
          }
        }

        PanelToolTip {
          visible: eyeArea.containsMouse
          text: (root.passwordRevealed ? "Hide password" : "Show password") + "  ·  Ctrl+Space"
        }
      }
    }
  }
}
