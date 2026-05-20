// Notification card. Pure presentational — no service, Notification, or
// ListModel references. The popup container drives lifetime; the history
// panel drives static rendering. Both use the same component.

import QtQuick
import QtQuick.Layouts
import qs.Commons

Rectangle {
  id: root

  property string app: ""
  property string appIcon: ""
  property string summary: ""
  property string body: ""
  property string image: ""
  // Nerd Font glyph rendered in the icon slot when no real icon is set.
  // Used by omarchy-notification-send so user-action toasts (`Silenced
  // notifications` etc.) show their bell/lock/etc. glyph without leaking
  // into the summary text.
  property string glyph: ""
  // NotificationUrgency: Low=0, Normal=1, Critical=2 (upstream).
  property int urgency: 1
  property double timestamp: 0
  property int cornerRadius: 0

  property real progress: 1.0
  property bool showProgress: false

  // System monospace font injected by the container.
  property string fontFamily: ""

  readonly property bool hovered: hoverTracker.hovered

  signal closeRequested()
  signal cardClicked()
  // Use only what the notification explicitly carries — no themed-icon
  // theme-lookup fallback because Quickshell's icon image provider returns
  // a placeholder for missing names (rather than erroring), which means
  // we'd render Qt's pink "broken image" pattern for any unknown app.
  // Apps that send their own icon via `image` (image-data hint) or
  // `appIcon` (-i flag) still get one.
  readonly property string smallIconSource: image.length > 0 ? image : appIcon
  readonly property bool hasGlyph: glyph.length > 0
  readonly property bool hasSmallIcon: smallIconSource.length > 0 || hasGlyph
  readonly property bool chromiumDerived: {
    var source = (app + "\n" + appIcon).toLowerCase()
    return source.indexOf("chrom") >= 0 || source.indexOf("brave") >= 0 ||
           source.indexOf("vivaldi") >= 0 || source.indexOf("microsoft-edge") >= 0 ||
           source.indexOf("opera") >= 0
  }
  readonly property string sanitizedBody: sanitizeBody(body)

  readonly property color dimColor: Qt.darker(Color.notifications.text, 1.4)
  readonly property color bodyColor: Qt.darker(Color.notifications.text, 1.15)
  readonly property color accentColor: urgency === 2 ? Color.urgent : (urgency === 0 ? dimColor : Color.notifications.countdown)

  function sanitizeBody(s) {
    var text = String(s).replace(/<img[^>]*>/gi, "")
    if (!chromiumDerived) return text

    // Chromium web notifications often prefix the body with the sending
    // origin, sometimes as a hyperlink. The browser icon already identifies
    // the source, so drop only that leading URL/domain.
    return text
      .replace(/^\s*<a\b[^>]*>\s*(?:https?:\/\/|www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:\/[^<\s]*)?\s*<\/a>\s*/i, "")
      .replace(/^\s*(?:https?:\/\/|www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:\/\S*)?\s+/i, "")
  }

  implicitWidth: Style.space(380)
  // Add 2 * border.width so mainColumn (inset by border.width on top/left/right)
  // doesn't push content under the bottom edge. The bottom edge is also inset
  // for symmetry except when the progress bar replaces it.
  implicitHeight: mainColumn.implicitHeight + border.width * 2
  radius: cornerRadius
  color: Color.notifications.background
  border.color: urgency === 2 ? Color.urgent : Color.notifications.border
  border.width: Math.max(1, Style.space(2))
  clip: true

  HoverHandler { id: hoverTracker }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.cardClicked()
  }

  ColumnLayout {
    id: mainColumn
    // Inset by the card border so the content doesn't paint over the card's
    // outer border.
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.topMargin: root.border.width
    anchors.leftMargin: root.border.width
    anchors.rightMargin: root.border.width
    spacing: 0

    // Text content.
    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: Style.space(12)
      Layout.rightMargin: Style.space(12)
      Layout.topMargin: Style.space(10)
      Layout.bottomMargin: Style.space(10)
      spacing: Style.space(12)

      Item {
        id: smallIconSlot
        Layout.preferredWidth: Style.space(40)
        Layout.preferredHeight: Style.space(40)
        Layout.alignment: Qt.AlignVCenter
        // Hide the slot when the icon failed to resolve (themed-icon name
        // not in the user's icon theme) AND we don't have a glyph fallback
        // — prevents rendering Qt's pink broken-image placeholder.
        visible: root.hasSmallIcon && (root.hasGlyph || smallIconImage.status !== Image.Error)

        Image {
          id: smallIconImage
          anchors.fill: parent
          source: root.smallIconSource
          sourceSize.width: smallIconSlot.width * Screen.devicePixelRatio
          sourceSize.height: smallIconSlot.height * Screen.devicePixelRatio
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          smooth: true
          visible: !root.hasGlyph || smallIconImage.status === Image.Ready
        }

        // Glyph fallback (Nerd Font character) when no image icon is
        // available. Used by omarchy-notification-send's `-g` flag.
        Text {
          anchors.centerIn: parent
          visible: root.hasGlyph && smallIconImage.status !== Image.Ready
          text: root.glyph
          color: Color.notifications.text
          font.family: root.fontFamily
          font.pixelSize: Style.font.iconLarge
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: Style.space(2)

        Text {
          Layout.fillWidth: true
          visible: root.summary.length > 0
          text: root.summary
          font.family: "Liberation Sans"
          color: Color.notifications.text
          font.pixelSize: Style.font.title
          font.bold: true
          wrapMode: Text.WordWrap
          elide: Text.ElideRight
          maximumLineCount: 2
        }

        Text {
          Layout.fillWidth: true
          Layout.topMargin: Style.space(2)
          visible: root.sanitizedBody.length > 0
          text: root.sanitizedBody
          textFormat: Text.StyledText
          font.family: "Liberation Sans"
          color: root.bodyColor
          font.pixelSize: Style.font.title
          wrapMode: Text.WordWrap
          elide: Text.ElideRight
          maximumLineCount: 3
        }
      }
    }
  }

  // Progress bar at the bottom edge. Stays visible while the container has
  // a finite lifetime; freezes (doesn't decrement) when hover pauses the
  // tick from the container side.
  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: Math.max(1, Style.space(3))
    color: Color.notifications.border
    visible: root.showProgress

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: parent.width * Math.max(0, Math.min(1, root.progress))
      color: root.accentColor
    }
  }
}
