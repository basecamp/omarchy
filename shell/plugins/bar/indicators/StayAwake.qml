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
    focusTarget: options
    contentWidth: fittedContentWidth(Style.space(232))
    contentHeight: fittedContentHeight(options.implicitHeight)
    onOpenChanged: if (open) Qt.callLater(function() { options.focusChoice(0) })

    Column {
      id: options
      width: parent.width
      spacing: Style.spacing.labelGap
      property int focusedIndex: 0

      function focusChoice(index) {
        focusedIndex = (index + choices.count + 1) % (choices.count + 1)
        var button = focusedIndex === choices.count ? turnOff : choices.itemAt(focusedIndex)
        if (button) button.forceActiveFocus()
      }

      Keys.onDownPressed: focusChoice(focusedIndex + 1)
      Keys.onUpPressed: focusChoice(focusedIndex - 1)
      Keys.onEscapePressed: root.close()

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
          focusable: true
          onActiveFocusChanged: if (activeFocus) options.focusedIndex = index
          onClicked: {
            if (root.idleService) {
              if (modelData.seconds > 0) root.idleService.stayAwakeFor(modelData.seconds)
              else root.idleService.setIdleEnabled(false)
            }
            root.close()
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
        focusable: true
        onActiveFocusChanged: if (activeFocus) options.focusedIndex = choices.count
        onClicked: {
          if (root.idleService) root.idleService.setIdleEnabled(true)
          root.close()
        }
      }
    }
  }
}
