import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Polkit
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "PolkitModel.js" as PolkitModel

Item {
  id: root

  property string fontFamily: Style.font.menuFamily
  // Bound to the central [polkit] section in shell.toml via Color.qml.
  property color accent: Color.polkit.accent
  property color background: Color.polkit.background
  property color foreground: Color.polkit.text
  property color border: Color.polkit.border
  property color borderError: Color.polkit.borderError
  property var borderSpec: Border.surfaceSpec("polkit", errorFlash ? "border-error" : "border", errorFlash ? borderError : border, Math.max(1, Style.space(2)), "border-alpha")
  property color scrim: Color.polkit.scrim
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int fieldHeight: Math.max(Style.space(42), Style.spacing.controlHeight)

  property bool closing: false
  property bool submitted: false
  property string currentMessage: ""
  property string currentPrompt: ""
  property string currentSupplementary: ""
  property bool responseRequired: false
  property bool responseVisible: false
  property bool failed: false
  property bool errorFlash: false
  // pam_fprintd appears in the polkit PAM stack (a sensor is enrolled).
  property bool fingerprintConfigured: false
  // pam_u2f appears in the polkit PAM stack.
  property bool fidoConfigured: false
  // Raw ordered methods from the PAM configuration.
  property var pamMethods: []
  // Filtered and ordered active methods based on capabilities and hardware state.
  readonly property var activeMethods: {
    var list = []
    for (var i = 0; i < pamMethods.length; i++) {
      var m = pamMethods[i]
      if (m === "fingerprint" && (!lidStateKnown || laptopClosed || !fingerprintConfigured)) continue
      if (m === "fido" && (!fidoStateKnown || !fidoTokenConnected || !fidoConfigured)) continue
      list.push(m)
    }
    return list
  }
  // Lid shut right now — the reader is physically unreachable, so we fall back
  // to the password even when a sensor is enrolled. Refreshed per request.
  property bool laptopClosed: false
  property bool lidStateKnown: false
  property bool fidoTokenConnected: false
  property bool fidoStateKnown: false
  property int shakeOffset: 0
  property bool waitingDelayLatched: false

  readonly property bool dialogVisible: polkitAgent.isActive || closing
  readonly property var authState: PolkitModel.authenticationState(currentPrompt, currentSupplementary, responseRequired)
  readonly property bool compactMode: dialogVisible && (authState.method === "waiting" || authState.method === "physical") && !submitted && !errorFlash
  readonly property bool waitingDelayActive: !waitingDelayLatched && !submitted && !errorFlash && authState.method === "waiting" && waitingDelayTimer.running
  readonly property int cardHeight: panel.height > 0 ? Math.min(fieldHeight + contentMargin * 2, panel.height - Style.gapsOut * 2) : fieldHeight + contentMargin * 2
  // Password mode is a wide field; compact modes collapse to a square that
  // just frames the centered sensor icon.
  readonly property int cardWidth: compactMode ? cardHeight : Math.min(Style.space(312), Math.max(Style.space(260), panel.width - Style.gapsOut * 2))

  Timer {
    id: waitingDelayTimer
    interval: 1000
    repeat: false
    onTriggered: root.waitingDelayLatched = true
  }

  function authorizationLabel(message) {
    return PolkitModel.authorizationLabel(message)
  }

  function loadPamConfig(raw) {
    var caps = PolkitModel.authCapabilitiesFromPamConfig(raw)
    fingerprintConfigured = caps.fingerprint
    fidoConfigured = caps.fido
    pamMethods = caps.methods || []
  }

  function refreshLidState() {
    root.lidStateKnown = false
    laptopClosedProc.running = false
    laptopClosedProc.running = true
  }

  function refreshFidoState() {
    root.fidoStateKnown = false
    fidoProbeProc.running = false
    fidoProbeProc.running = true
  }

  function finishWaitingDelay() {
    waitingDelayLatched = true
    waitingDelayTimer.stop()
  }

  function resetSnapshot() {
    currentMessage = ""
    currentPrompt = ""
    currentSupplementary = ""
    responseRequired = false
    responseVisible = false
    failed = false
    errorFlash = false
    submitted = false
    passwordInput.text = ""
    waitingDelayTimer.stop()
    waitingDelayLatched = false
    lidStateKnown = false
    fidoStateKnown = false
    fidoTokenConnected = false
    fidoProbeProc.running = false
  }

  function syncFromFlow() {
    var flow = polkitAgent.flow
    if (!flow) return

    currentMessage = String(flow.message || "Authentication is needed...")
    currentPrompt = String(flow.inputPrompt || "")
    currentSupplementary = String(flow.supplementaryMessage || "")
    responseRequired = !!flow.isResponseRequired
    responseVisible = !!flow.responseVisible
    failed = !!flow.failed

    if (responseRequired) submitted = false
    if (authState.method !== "waiting") finishWaitingDelay()
  }

  function beginFlow() {
    closeTimer.stop()
    waitingDelayLatched = false
    waitingDelayTimer.restart()
    closing = false
    submitted = false
    passwordInput.text = ""
    refreshLidState()
    refreshFidoState()
    syncFromFlow()
    Qt.callLater(refocus)
  }

  function refocus() {
    if (!dialogVisible) return
    // While PAM is handling a non-interactive prompt, park focus on the key
    // catcher so Escape still cancels without sending an empty response.
    if (compactMode || !responseRequired) keyCatcher.forceActiveFocus()
    else passwordInput.forceActiveFocus()
  }

  function submitResponse() {
    var flow = polkitAgent.flow
    if (!flow || !flow.isResponseRequired) return
    finishWaitingDelay()
    submitted = true
    errorFlash = false
    flow.submit(passwordInput.text)
    passwordInput.text = ""
    keyCatcher.forceActiveFocus()
  }

  function cancelRequest() {
    var flow = polkitAgent.flow
    passwordInput.text = ""
    submitted = false
    closing = true
    closeTimer.restart()
    if (flow) flow.cancelAuthenticationRequest()
  }

  function triggerFailureFeedback() {
    finishWaitingDelay()
    submitted = false
    errorFlash = true
    passwordInput.text = ""
    errorTimer.restart()
    shakeAnimation.restart()
    Qt.callLater(refocus)
  }

  Timer {
    id: closeTimer
    interval: 300
    repeat: false
    onTriggered: {
      closing = false
      resetSnapshot()
    }
  }

  Timer {
    id: errorTimer
    interval: 1200
    repeat: false
    onTriggered: root.errorFlash = false
  }

  SequentialAnimation {
    id: shakeAnimation
    NumberAnimation { target: root; property: "shakeOffset"; to: -8; duration: 35; easing.type: Easing.OutQuad }
    NumberAnimation { target: root; property: "shakeOffset"; to: 8; duration: 50; easing.type: Easing.InOutQuad }
    NumberAnimation { target: root; property: "shakeOffset"; to: 0; duration: 55; easing.type: Easing.OutQuad }
  }

  FileView {
    path: "/etc/pam.d/polkit-1"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadPamConfig(text())
    onLoadFailed: {
      root.fingerprintConfigured = false
      root.fidoConfigured = false
    }
    onFileChanged: reload()
  }

  Process {
    id: laptopClosedProc
    command: ["bash", "-c", "omarchy-hw-laptop-closed && echo closed || echo open"]
    stdout: StdioCollector { id: laptopClosedOut; waitForEnd: true }
    onExited: {
      root.laptopClosed = String(laptopClosedOut.text || "").trim() === "closed"
      root.lidStateKnown = true
    }
  }

  Process {
    id: fidoProbeProc
    command: ["bash", "-c", "for d in /sys/class/hidraw/hidraw*; do [ -e \"$d\" ] && udevadm info --query=property --path=\"$d\"; done"]
    stdout: StdioCollector { id: fidoProbeOut; waitForEnd: true }
    onExited: {
      var out = String(fidoProbeOut.text || "")
      root.fidoTokenConnected = out.indexOf("ID_SECURITY_TOKEN=1") !== -1 || out.indexOf("ID_FIDO_TOKEN=1") !== -1
      root.fidoStateKnown = true
    }
  }

  PolkitAgent {
    id: polkitAgent
    path: "/org/omarchy/PolkitAgent"

    onAuthenticationRequestStarted: root.beginFlow()
    onIsActiveChanged: {
      if (isActive) root.syncFromFlow()
      else if (!root.closing) root.resetSnapshot()
    }
    onIsRegisteredChanged: {
      if (isRegistered) console.log("omarchy polkit agent registered")
      else console.warn("omarchy polkit agent is not registered; another agent may be running")
    }
  }

  Connections {
    target: polkitAgent.flow

    function onIsResponseRequiredChanged() {
      root.syncFromFlow()
      if (!polkitAgent.flow || !polkitAgent.flow.isResponseRequired) passwordInput.text = ""
      Qt.callLater(root.refocus)
    }

    function onInputPromptChanged() { root.syncFromFlow() }
    function onResponseVisibleChanged() { root.syncFromFlow() }
    function onSupplementaryMessageChanged() { root.syncFromFlow() }
    function onFailedChanged() { root.syncFromFlow() }

    function onAuthenticationFailed() {
      root.syncFromFlow()
      root.triggerFailureFeedback()
    }

    function onAuthenticationSucceeded() {
      root.closing = true
      closeTimer.restart()
    }

    function onAuthenticationRequestCancelled() {
      root.closing = true
      closeTimer.restart()
    }
  }

  PanelWindow {
    id: panel
    visible: root.dialogVisible
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-polkit"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.refocus()
    }

    Item {
      id: cardContainer
      width: (root.compactMode && root.activeMethods.length > 1)
             ? (root.cardHeight * root.activeMethods.length + Style.space(12) * (root.activeMethods.length - 1))
             : root.cardWidth
      height: root.cardHeight
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: root.shakeOffset
      opacity: root.waitingDelayActive ? 0.0 : 1.0

      MouseArea { anchors.fill: parent; onClicked: root.refocus() }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.cancelRequest()
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.responseRequired) root.submitResponse()
            event.accepted = true
          }
        }
      }

      BorderSurface {
        id: card
        anchors.fill: parent
        visible: !(root.compactMode && root.activeMethods.length > 1)
        radius: root.cornerRadius
        color: root.background
        borderSpec: root.borderSpec
        padding: root.contentMargin

        MouseArea { anchors.fill: parent; onClicked: root.refocus() }

        OpticalGlyph {
          anchors.centerIn: parent
          width: Math.round(root.fieldHeight * 0.7)
          height: width
          visible: root.compactMode && root.activeMethods.length === 1
          text: root.activeMethods.length === 1 ? (root.activeMethods[0] === "fido" ? "\udb80\udf06" : "\udb80\ude37") : ""
          fontFamily: root.fontFamily
          fontSize: Math.round(root.fieldHeight * 0.7)
          color: root.errorFlash ? Color.polkit.textError : Util.alpha(root.accent, 0.55)
        }

        OpticalGlyph {
          anchors.centerIn: parent
          width: Math.round(root.fieldHeight * 0.7)
          height: width
          visible: root.compactMode && root.activeMethods.length === 0
          text: "\uf023"
          fontFamily: root.fontFamily
          fontSize: Style.font.iconLarge
          color: root.errorFlash ? Color.polkit.textError : root.accent
        }

        Row {
          id: cardRow
          visible: !root.compactMode
          anchors.fill: parent
          anchors.topMargin: card.contentTopInset
          anchors.rightMargin: card.contentRightInset
          anchors.bottomMargin: card.contentBottomInset
          anchors.leftMargin: card.contentLeftInset
          spacing: Style.space(14)

          Text {
            text: "\uf023"
            color: root.errorFlash ? Color.polkit.textError : root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.iconLarge
            width: Style.space(26)
            height: root.fieldHeight
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
          }

          Item {
            width: parent.width - Style.space(40)
            height: root.fieldHeight

            TextInput {
              id: passwordInput
              anchors.fill: parent
              verticalAlignment: TextInput.AlignVCenter
              activeFocusOnPress: true
              clip: true
              selectionColor: Util.alpha(root.accent, 0.45)
              selectedTextColor: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.iconLarge
              echoMode: root.responseVisible ? TextInput.Normal : TextInput.Password
              passwordCharacter: "\u2022"
              color: root.errorFlash ? Color.polkit.textError : root.foreground
              cursorVisible: activeFocus && root.responseRequired && !root.submitted && !root.errorFlash
              readOnly: !root.responseRequired || root.submitted || root.errorFlash
              enabled: root.dialogVisible && root.responseRequired
              onAccepted: root.submitResponse()
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.cancelRequest()
                  event.accepted = true
                }
              }
            }

            Text {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.errorFlash ? "Wrong" : (root.submitted ? "Checking..." : root.authState.prompt)
              color: root.errorFlash ? Color.polkit.textError : root.foreground
              opacity: root.errorFlash ? 1 : 0.36
              font.family: root.fontFamily
              font.pixelSize: Style.font.iconLarge
              elide: Text.ElideRight
              visible: passwordInput.text.length === 0
            }

            Rectangle {
              width: Math.max(1, Style.space(2))
              height: Style.space(24)
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              color: root.errorFlash ? Color.polkit.textError : root.foreground
              visible: passwordInput.visible && passwordInput.activeFocus && root.responseRequired && passwordInput.text.length === 0 && !root.submitted && !root.errorFlash
            }

            MouseArea {
              anchors.fill: parent
              acceptedButtons: Qt.LeftButton
              enabled: passwordInput.enabled
              onClicked: passwordInput.forceActiveFocus()
            }
          }
        }
      }

      Row {
        id: capabilityRow
        anchors.centerIn: parent
        spacing: Style.space(12)
        visible: root.compactMode && root.activeMethods.length > 1

        Repeater {
          model: root.activeMethods

          BorderSurface {
            width: root.cardHeight
            height: root.cardHeight
            radius: root.cornerRadius
            color: root.background
            borderSpec: root.borderSpec
            padding: root.contentMargin

            OpticalGlyph {
              anchors.centerIn: parent
              width: Math.round(root.fieldHeight * 0.7)
              height: width
              text: modelData === "fido" ? "\udb80\udf06" : "\udb80\ude37"
              fontFamily: root.fontFamily
              fontSize: Math.round(root.fieldHeight * 0.7)
              // First available method is primary (slightly stronger but still muted), others are secondary fallbacks
              color: root.errorFlash ? Color.polkit.textError
                     : (index === 0 ? Util.alpha(root.accent, 0.55) : Util.alpha(root.accent, 0.25))
            }
          }
        }
      }
    }

    Rectangle {
      id: cuePill
      visible: root.compactMode && root.authState.method === "physical"
      width: Math.min(cueText.implicitWidth + Style.space(24), panel.width - Style.gapsOut * 2)
      height: Style.space(28)
      anchors.horizontalCenter: cardContainer.horizontalCenter
      anchors.bottom: cardContainer.top
      anchors.bottomMargin: Style.space(10)
      opacity: root.waitingDelayActive ? 0.0 : 1.0
      radius: root.cornerRadius
      color: root.background

      Text {
        id: cueText
        anchors.fill: parent
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        text: root.authState.prompt
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideMiddle
      }
    }

    Rectangle {
      id: justificationPill
      width: Math.min(justificationText.implicitWidth + Style.space(24), panel.width - Style.gapsOut * 2)
      height: Style.space(28)
      anchors.horizontalCenter: cardContainer.horizontalCenter
      anchors.bottom: cuePill.visible ? cuePill.top : cardContainer.top
      anchors.bottomMargin: Style.space(10)
      radius: root.cornerRadius
      color: root.background
      opacity: root.waitingDelayActive ? 0.0 : 1.0

      Text {
        id: justificationText
        anchors.fill: parent
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        text: root.authorizationLabel(root.currentMessage)
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideMiddle
      }
    }
  }
}
