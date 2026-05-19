import QtQuick
import QtQuick.Effects
import qs.Commons

Item {
  id: root

  property string backgroundPath: ""
  property int backgroundVersion: 0
  property bool fingerprintConfigured: false
  property bool authenticatingPassword: false
  property string failureMessage: ""
  property int failedAttempts: 0
  property bool inputEnabled: true
  property real scaleFactor: 1
  property bool hasTyped: false

  readonly property string fingerprintGlyph: "\uDB80\uDE37"
  readonly property string placeholderText: fingerprintConfigured ? "Enter Password " + fingerprintGlyph : "Enter Password"
  readonly property real effectiveScale: Math.max(1, scaleFactor)
  readonly property int fieldWidth: Math.round(650 / effectiveScale)
  readonly property int fieldHeight: Math.round(100 / effectiveScale)
  readonly property int outlineThickness: Math.max(1, Math.round(4 / effectiveScale))
  readonly property int fieldFontSize: Style.font.heading

  signal submitPassword(string password)
  signal clearFailureRequested()
  signal wakeRequested()

  function withAlpha(color, alpha) {
    return Qt.rgba(color.r, color.g, color.b, alpha)
  }

  function fileUrl(path) {
    if (!path) return ""
    var encoded = String(path).split("/").map(encodeURIComponent).join("/")
    return "file://" + encoded + "?v=" + backgroundVersion
  }

  function forcePasswordFocus() {
    passwordInput.forceActiveFocus()
  }

  function clearPassword() {
    passwordInput.text = ""
    hasTyped = false
  }

  onInputEnabledChanged: {
    hasTyped = false
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }
  Component.onCompleted: {
    hasTyped = false
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }

  Rectangle {
    anchors.fill: parent
    color: Color.background

    Image {
      id: wallpaper
      anchors.fill: parent
      source: root.fileUrl(root.backgroundPath)
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: false
      sourceSize.width: width
      sourceSize.height: height
    }

    MultiEffect {
      anchors.fill: wallpaper
      source: wallpaper
      blurEnabled: wallpaper.status === Image.Ready
      blur: 1.0
      blurMax: 64
      blurMultiplier: 1.0
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onClicked: { root.wakeRequested(); root.forcePasswordFocus() }
      onPositionChanged: root.wakeRequested()
    }

    Rectangle {
      id: inputField
      width: root.fieldWidth
      height: root.fieldHeight
      anchors.centerIn: parent
      color: Color.lock.background
      border.color: root.failureMessage.length > 0 ? Color.lock.borderError : (root.authenticatingPassword ? Color.lock.borderActive : Color.lock.border)
      border.width: root.outlineThickness
      radius: Style.cornerRadius
      clip: true

      TextInput {
        id: passwordInput
        anchors.fill: parent
        anchors.leftMargin: root.outlineThickness + 18
        anchors.rightMargin: root.outlineThickness + 18
        verticalAlignment: TextInput.AlignVCenter
        horizontalAlignment: TextInput.AlignHCenter
        activeFocusOnPress: true
        clip: true
        enabled: root.inputEnabled && !root.authenticatingPassword
        readOnly: root.authenticatingPassword
        echoMode: TextInput.Password
        passwordCharacter: "\u2022"
        passwordMaskDelay: 0
        color: Color.lock.text
        selectionColor: Color.lock.selection
        selectedTextColor: Color.lock.text
        font.family: "monospace"
        font.pixelSize: root.fieldFontSize
        cursorVisible: activeFocus && !root.authenticatingPassword && root.hasTyped

        onTextChanged: {
          if (text.length > 0) {
            root.hasTyped = true
            root.wakeRequested()
          }
          if (text.length > 0 && root.failureMessage.length > 0) root.clearFailureRequested()
        }

        onAccepted: {
          var submitted = text
          text = ""
          root.hasTyped = false
          if (submitted.length > 0) root.submitPassword(submitted)
        }

        Keys.onPressed: function(event) {
          root.wakeRequested()
          if (event.key === Qt.Key_Escape || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U)) {
            text = ""
            root.hasTyped = false
            event.accepted = true
          }
        }
      }

      Text {
        anchors.fill: passwordInput
        text: root.authenticatingPassword ? "Checking…" : (root.failureMessage.length > 0 ? root.failureMessage : root.placeholderText)
        visible: passwordInput.text.length === 0
        color: (!root.authenticatingPassword && root.failureMessage.length > 0) ? Color.lock.textError : Color.lock.text
        font.family: "monospace"
        font.pixelSize: root.fieldFontSize
        font.italic: !root.authenticatingPassword && root.failureMessage.length > 0
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
      }
    }
  }
}
