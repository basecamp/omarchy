import QtQuick
import qs.Ui
import qs.Commons

BarIndicator {
  id: root

  readonly property var idleService: bar?.shell?.firstPartyServiceFor("omarchy.idle")

  active: idleService ? idleService.stayAwake : false
  activeText: "󰅶"
  inactiveText: "󰅶"
  activeTooltipText: idleService && idleService.stayAwakeUntil > 0
    ? "Stay Awake until " + Qt.formatTime(new Date(idleService.stayAwakeUntil), "hh:mm") + " · Right-click for options"
    : "Allow Idle Lock & Screensaver · Right-click for options"
  inactiveTooltipText: "Stay Awake · Right-click for options"

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

  PopupCard {
    id: durationPopup
    anchorItem: root
    owner: root
    bar: root.bar
    contentWidth: fittedContentWidth(Style.space(260))
    contentHeight: fittedContentHeight(options.implicitHeight)

    Column {
      id: options
      width: parent.width
      spacing: Style.space(4)
      focus: durationPopup.open
      Keys.onEscapePressed: root.close()

      Text {
        text: "Keep awake"
        color: Color.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        height: implicitHeight + Style.space(8)
      }

      Repeater {
        model: [
          { label: "For 30 minutes", seconds: 1800 },
          { label: "For 1 hour", seconds: 3600 },
          { label: "For 3 hours", seconds: 10800 },
          { label: "For 8 hours", seconds: 28800 },
          { label: "Indefinitely", seconds: 0 },
          { label: "Turn off", seconds: -1 }
        ]

        Button {
          required property var modelData
          width: options.width
          text: modelData.label
          leftAlign: true
          focusable: true
          onClicked: {
            if (root.idleService) {
              if (modelData.seconds > 0) root.idleService.stayAwakeFor(modelData.seconds)
              else root.idleService.setIdleEnabled(modelData.seconds < 0)
            }
            root.close()
          }
        }
      }
    }
  }
}
