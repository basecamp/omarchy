import QtQuick
import Quickshell
import Quickshell.Networking
import qs.Commons
import "mocks"
import "network" as Network

ShellRoot {
  id: test
  property bool failed: false
  function check(ok, message) {
    if (!ok) {
      failed = true
      console.log("RESULT fail " + message)
    }
  }

  // Not visible in the normal test run. The optional preview maps the real
  // KeyboardPanel for a screenshot, without ever altering the host network.
  Item {
    Network.Panel {
      id: panel
      bar: QtObject {
        property color foreground: Color.foreground
        property color barForeground: Color.foreground
        property color urgent: Color.urgent
        property string fontFamily: Style.font.family
        property string position: "top"
        property int barSize: 24
        property bool vertical: false
        property bool foregroundAnimationEnabled: false
        property var activePopout: null
        function requestPopout(owner) { activePopout = owner }
        function releasePopout(owner) { activePopout = null }
        function registerClickTarget(target) {}
        function unregisterClickTarget(target) {}
        function hideTooltip(target) {}
        function showTooltip(target, text) {}
      }
    }
  }

  Timer {
    interval: 250
    running: true
    onTriggered: {
      test.check(panel.kind === "wifi", "connected Wi-Fi fixture")
      test.check(panel.connectivity === "full", "normal connectivity")
      test.check(!panel.testButton.visible && !panel.testBarButton.active, "no false portal banner")
      test.check(!panel.testPoll.running, "normal connectivity adds no polling")
      test.check(NetworkMock.checks > 0, "checks at connection/startup")
      var before = NetworkMock.checks
      panel.checkConnectivity()
      test.check(NetworkMock.checks === before + 1, "manual check delegates to NM")
      NetworkMock.connectivity = NetworkConnectivity.Portal
      Qt.callLater(portalChecks)
    }
  }

  function portalChecks() {
    check(panel.hasCaptivePortal && panel.restricted, "native portal activates restricted mode")
    check(panel.testButton.visible, "portal button visible")
    check(panel.testButton.text === "Open Captive Portal", "prominent action label")
    check(panel.icon === "󰤩" && panel.testBarButton.active, "blocked bar icon and warning color")
    check(panel.testMeta.text === "SIGN-IN REQUIRED", "status replaces cheerful connection phrase")
    check(panel.testTitle.text === "Guest Wi-Fi", "connected SSID survives missing route details")
    check(panel.testPoll.running && panel.testPoll.interval === 10000, "restricted recheck runs while closed")
    var before = NetworkMock.checks
    panel.testPoll.triggered()
    check(NetworkMock.checks === before + 1, "background timer rechecks through NM")
    panel.testKeys.textKey("r")
    check(NetworkMock.checks === before + 2, "r requests fresh connectivity")
    // Exercise the existing cursor model, not a separate test-only action.
    panel.cursorActive = true
    panel.focusSection = "header"
    panel.testKeys.moveRequested(0, 1)
    check(panel.focusSection === "portal", "down from header reaches portal")
    panel.testKeys.moveRequested(0, 1)
    check(panel.focusSection === "dns", "down from portal skips absent band")
    panel.testKeys.moveRequested(0, -1)
    check(panel.focusSection === "portal", "up from DNS reaches portal")
    panel.bandAvailable = ["2.4", "5"]
    panel.testKeys.moveRequested(0, 1)
    check(panel.focusSection === "band", "down from portal reaches available band")
    panel.testKeys.moveRequested(0, -1)
    check(panel.focusSection === "portal", "up from band reaches portal")
    panel.testKeys.activateRequested()
    NetworkMock.connectivity = NetworkConnectivity.Full
    Qt.callLater(recoveryChecks)
  }

  function recoveryChecks() {
    check(!panel.hasCaptivePortal && !panel.restricted, "login recovery clears restriction")
    check(!panel.testPoll.running, "recovery stops extra checks")
    check(!panel.testButton.visible && !panel.testBarButton.active, "recovery hides button and warning color")
    check(panel.focusSection === "header", "disappearing button leaves valid cursor")
    check(panel.icon !== "󰤩", "signal icon returns")
    // No browser launch when the portal is gone (runner asserts one launch).
    panel.openCaptivePortal()
    NetworkMock.connectivity = NetworkConnectivity.Limited
    Qt.callLater(limitedChecks)
  }

  function limitedChecks() {
    check(panel.restricted && !panel.hasCaptivePortal, "outage is not mislabelled as a portal")
    check(!panel.testButton.visible && panel.testMeta.text === "LIMITED INTERNET ACCESS", "limited state has no login button")
    NetworkMock.connectivity = NetworkConnectivity.Portal
    NetworkMock.connectivityCheckEnabled = false
    Qt.callLater(disabledChecks)
  }

  function disabledChecks() {
    check(!panel.hasCaptivePortal && panel.connectivity === "unknown", "disabled checks ignore cached portal")
    check(!panel.testPoll.running, "disabled checks stop polling")
    var before = NetworkMock.checks
    panel.checkConnectivity()
    check(NetworkMock.checks === before, "does not enable or invoke disabled checks")
    NetworkMock.connectivityCheckEnabled = true
    NetworkMock.network.connected = false
    NetworkMock.wifi.connected = false
    Qt.callLater(disconnectedChecks)
  }

  function disconnectedChecks() {
    check(panel.kind === "disconnected" && !panel.hasCaptivePortal, "disconnect clears stale portal")
    check(!panel.testButton.visible && panel.icon === "󰤮", "disconnected icon not portal icon")
    if (failed) { Qt.quit(); return }
    console.log("RESULT pass")
    var preview = Quickshell.env("NETWORK_TEST_PREVIEW")
    if (preview === "portal" || preview === "full") {
      NetworkMock.network.connected = true
      NetworkMock.wifi.connected = true
      NetworkMock.connectivity = preview === "portal" ? NetworkConnectivity.Portal : NetworkConnectivity.Full
      panel.open()
      previewCapture.start()
      previewDone.start()
    } else {
      // Give the detached, stubbed browser command time to append its argv.
      done.start()
    }
  }

  // Optional fresh, panel-only captures. Rendering the card itself excludes
  // the host desktop, and the network details above come only from fixtures.
  // NETWORK_TEST_PREVIEW=portal (or full), NETWORK_TEST_SCREENSHOT=/tmp/new.png
  Timer {
    id: previewCapture
    interval: 750
    onTriggered: {
      var path = Quickshell.env("NETWORK_TEST_SCREENSHOT")
      if (!path) return
      var card = panel.testKeys.parent.parent
      card.grabToImage(function(result) {
        test.check(result.saveToFile(path), "save fresh preview screenshot")
        Qt.quit()
      })
    }
  }
  Timer { id: done; interval: 300; onTriggered: Qt.quit() }
  Timer { id: previewDone; interval: 15000; onTriggered: Qt.quit() }
}
