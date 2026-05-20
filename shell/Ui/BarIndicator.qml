import QtQuick
import qs.Commons

WidgetButton {
  id: root

  property string moduleName: ""
  property var settings: ({})
  property string activeText: ""
  property string inactiveText: activeText
  property string activeTooltipText: ""
  property string inactiveTooltipText: activeTooltipText
  property string indicatorBlock: "single"
  readonly property bool belongsInBlock: indicatorBlock === "active" ? active : (indicatorBlock === "inactive" ? !active : true)
  readonly property bool inactiveRevealed: !active && !!bar && bar.revealInactiveIndicators

  function extractData(raw) {
    var text = String(raw || "").trim()
    if (text === "") return {}

    var lines = text.split("\n")
    try {
      return JSON.parse(lines[lines.length - 1])
    } catch (error) {
      return { text: text }
    }
  }

  function syncIndicatorOpacity() {
    root.opacity = !belongsInBlock ? 0 : (active ? 1 : (inactiveRevealed ? 0.45 : 0))
  }

  Component.onCompleted: syncIndicatorOpacity()
  onActiveChanged: syncIndicatorOpacity()
  onBarChanged: syncIndicatorOpacity()
  onBelongsInBlockChanged: syncIndicatorOpacity()
  onInactiveRevealedChanged: syncIndicatorOpacity()
  onIndicatorBlockChanged: syncIndicatorOpacity()

  visible: belongsInBlock && (text !== "" || keepSpace)
  text: active ? activeText : inactiveText
  tooltipText: active ? activeTooltipText : inactiveTooltipText
  keepSpace: true
  dimmed: !active
  concealed: !active && !inactiveRevealed
  interactive: belongsInBlock && (active || indicatorBlock === "inactive" || inactiveRevealed)
  useActiveColor: false
  maintainIndicatorReveal: indicatorBlock === "inactive"
  fontSize: Style.font.caption
  horizontalMargin: 5
  verticalPadding: 5
}
