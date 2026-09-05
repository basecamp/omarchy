import QtQuick
import qs.Commons
import qs.Ui

BarIndicator {
  id: root

  readonly property var idleService: bar?.shell?.firstPartyServiceFor("omarchy.idle")

  active: idleService ? idleService.stayAwake : false
  activeText: "󰅶"
  inactiveText: "󰅶"
  activeTooltipText: idleService && idleService.stayAwakeUntil > 0
    ? "Stay Awake until " + Qt.formatTime(new Date(idleService.stayAwakeUntil), "hh:mm") + "\nRight-click for duration"
    : "Allow Idle Lock & Screensaver\nRight-click for duration"
  inactiveTooltipText: "Stay Awake\nRight-click for duration"

  function toggle() {
    if (root.idleService) root.idleService.setIdleEnabled(root.active)
  }

  function close() { durationPopup.open = false }

  onPressed: function(button) {
    if (button === Qt.RightButton) durationPopup.open = !durationPopup.open
    else if (button === Qt.LeftButton) {
      root.close()
      root.toggle()
    }
  }

  KeyboardPanel {
    id: durationPopup
    anchorItem: root
    owner: root
    bar: root.bar
    focusTarget: keys
    contentWidth: fittedContentWidth(Style.space(232))
    contentHeight: fittedContentHeight(options.implicitHeight)
    onOpenChanged: if (open) keys.currentIndex = 0

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      property int currentIndex: 0

      function moveChoice(direction) {
        currentIndex = (currentIndex + direction + choices.count + 1) % (choices.count + 1)
      }

      onMoveRequested: function(dx, dy) { if (dy) moveChoice(dy) }
      onTabRequested: function(direction) { moveChoice(direction) }
      onActivateRequested: {
        var button = currentIndex === choices.count ? turnOff : choices.itemAt(currentIndex)
        if (button) button.clicked()
      }
      onCloseRequested: root.close()

      Column {
        id: options
        width: parent.width
        spacing: Style.spacing.labelGap

        Text {
          text: "Stay awake"
          textFormat: Text.PlainText
          color: Color.popups.text
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          leftPadding: Style.spacing.controlPaddingX
          height: implicitHeight + Style.space(8)
        }

        Repeater {
          id: choices
          model: [
            { label: "30 minutes", seconds: 1800 },
            { label: "1 hour", seconds: 3600 },
            { label: "3 hours", seconds: 10800 },
            { label: "8 hours", seconds: 28800 },
            { label: "Indefinitely", seconds: 0 }
          ]

          Button {
            required property var modelData
            required property int index
            width: options.width
            text: modelData.label
            foreground: Color.popups.text
            leftAlign: true
            hasCursor: keys.currentIndex === index
            onHovered: function(hovered) { if (hovered) keys.currentIndex = index }
            onClicked: {
              root.close()
              if (root.idleService) {
                if (modelData.seconds > 0) root.idleService.stayAwakeFor(modelData.seconds)
                else root.idleService.setIdleEnabled(false)
              }
            }
          }
        }

        PanelSeparator { foreground: Color.popups.text }

        Button {
          id: turnOff
          width: options.width
          text: "Turn off"
          foreground: Color.popups.text
          leftAlign: true
          hasCursor: keys.currentIndex === choices.count
          onHovered: function(hovered) { if (hovered) keys.currentIndex = choices.count }
          onClicked: {
            root.close()
            if (root.idleService) root.idleService.setIdleEnabled(true)
          }
        }
      }
    }
  }
}
