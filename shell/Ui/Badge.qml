import QtQuick
import qs.Commons

// Badge: small count/status pill for taskbar buttons, tray icons, and list
// rows. `tone` picks the semantic state color; `count` renders a number,
// `text` renders a short label. Color-blind-safe rule: never rely on color
// alone — badges carry a count, glyph, or text.
Rectangle {
  id: root

  property int count: -1
  property string text: ""

  // "accent" | "danger" | "success" | "warning" | "info"
  property string tone: "accent"

  readonly property color _tone: tone === "danger" ? Tokens.state.danger
    : tone === "success" ? Tokens.state.success
    : tone === "warning" ? Tokens.state.warning
    : tone === "info" ? Tokens.state.info
    : Tokens.accent.primary

  implicitWidth: Math.max(implicitHeight, label.implicitWidth + Style.space(8))
  implicitHeight: Math.max(16, Math.round(Style.font.body * 1.3))
  radius: height / 2
  color: Util.alpha(_tone, 0.85)

  Text {
    id: label
    anchors.centerIn: parent
    text: root.count >= 0 ? (root.count > 99 ? "99+" : String(root.count)) : root.text
    color: Tokens.surface.base
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    font.bold: true
  }
}
