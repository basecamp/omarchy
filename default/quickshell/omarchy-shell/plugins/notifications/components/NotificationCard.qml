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
  property int cornerRadius: 10

  property real progress: 1.0
  property bool showProgress: false

  // System font from shell.json bar.fontFamily, injected by the container.
  property string fontFamily: ""

  readonly property bool hovered: hoverTracker.hovered

  signal closeRequested()
  signal cardClicked()
  signal imageClicked()

  // Media mode = the notification carries a real screenshot or screen
  // recording preview. Quickshell normalizes file paths from `-i` and the
  // `image-path` hint into `image://icon//<absolute path>` (double slash
  // marks an absolute filesystem path vs a themed icon name like
  // `image://icon/firefox`).
  function _imageFilePath(s) {
    if (!s) return ""
    if (s.indexOf("image://icon//") === 0) return s.substring("image://icon/".length)
    if (s.indexOf("file://") === 0) return decodeURIComponent(s.substring(7))
    return ""
  }
  function _isMediaFile(path) {
    if (!path) return false
    var lower = path.toLowerCase()
    return lower.endsWith(".png") || lower.endsWith(".jpg") ||
           lower.endsWith(".jpeg") || lower.endsWith(".webp") ||
           lower.endsWith(".gif")
  }
  readonly property string mediaImageSource: ""
  readonly property bool mediaMode: false
  // Use only what the notification explicitly carries — no themed-icon
  // theme-lookup fallback because Quickshell's icon image provider returns
  // a placeholder for missing names (rather than erroring), which means
  // we'd render Qt's pink "broken image" pattern for any unknown app.
  // Apps that send their own icon via `image` (image-data hint) or
  // `appIcon` (-i flag) still get one.
  readonly property string smallIconSource: image.length > 0 ? image : appIcon
  readonly property bool hasGlyph: glyph.length > 0
  readonly property bool inlineGlyph: summary.match(/^\S\s{2,}/) !== null
  readonly property bool hasSmallIcon: !mediaMode && !inlineGlyph && (smallIconSource.length > 0 || hasGlyph)

  readonly property color dimColor: Qt.darker(Color.notifications.text, 1.4)
  readonly property color bodyColor: Qt.darker(Color.notifications.text, 1.15)
  readonly property color hoverColor: Qt.rgba(Color.notifications.text.r, Color.notifications.text.g, Color.notifications.text.b, 0.14)
  readonly property color accentColor: urgency === 2 ? Color.urgent : (urgency === 0 ? dimColor : Color.notifications.countdown)

  function sanitizeBody(s) {
    return String(s).replace(/<img[^>]*>/gi, "")
  }

  implicitWidth: 380
  // Add 2 * border.width so mainColumn (inset by border.width on top/left/right)
  // doesn't push content under the bottom edge. The bottom edge is also inset
  // for symmetry except when the progress bar replaces it.
  implicitHeight: mainColumn.implicitHeight + border.width * 2
  radius: cornerRadius
  color: Color.notifications.background
  border.color: urgency === 2 ? Color.urgent : Color.notifications.border
  border.width: 2
  clip: true

  HoverHandler { id: hoverTracker }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.cardClicked()
  }

  ColumnLayout {
    id: mainColumn
    // Inset by the card border so the hero image (and the text row) don't
    // paint over the card's outer border. Without this the left/right/top
    // border is invisible under the image.
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.topMargin: root.border.width
    anchors.leftMargin: root.border.width
    anchors.rightMargin: root.border.width
    spacing: 0

    // Hero image strip (media notifications only). PreserveAspectCrop so
    // the preview looks like a clean banner without dark letterboxing.
    Item {
      Layout.fillWidth: true
      Layout.preferredHeight: 140
      visible: root.mediaMode
      clip: true

      Image {
        anchors.fill: parent
        source: root.mediaImageSource
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: width > 0 ? width * Screen.devicePixelRatio : 0
        sourceSize.height: height > 0 ? height * Screen.devicePixelRatio : 0
        asynchronous: true
        smooth: true
        cache: false
      }

      // Bottom divider matching the card border so the screenshot is
      // visually framed on every side (card border wraps top/left/right;
      // this line completes the bottom).
      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.border.width
        color: root.urgency === 2 ? Color.urgent : Color.notifications.border
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.imageClicked()
      }

    }

    // Text content. Always rendered — for media notifications this carries
    // the summary/body ("Screenshot saved" etc) under the hero image.
    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: 12
      Layout.rightMargin: 12
      Layout.topMargin: 10
      Layout.bottomMargin: 10
      spacing: 12

      Item {
        id: smallIconSlot
        Layout.preferredWidth: 40
        Layout.preferredHeight: 40
        Layout.alignment: Qt.AlignVCenter
        // Hide the slot when the icon failed to resolve (themed-icon name
        // not in the user's icon theme) AND we don't have a glyph fallback
        // — prevents rendering Qt's pink broken-image placeholder.
        visible: root.hasGlyph || (!root.mediaMode && smallIconSource.length > 0 && smallIconImage.status !== Image.Error)

        Image {
          id: smallIconImage
          anchors.fill: parent
          source: root.smallIconSource
          sourceSize.width: 40 * Screen.devicePixelRatio
          sourceSize.height: 40 * Screen.devicePixelRatio
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
          font.pixelSize: 18
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: 2

        Text {
          Layout.fillWidth: true
          visible: root.summary.length > 0
          text: root.summary
          font.family: root.fontFamily
          color: Color.notifications.text
          font.pixelSize: 13
          font.bold: true
          wrapMode: Text.WordWrap
          elide: Text.ElideRight
          maximumLineCount: 2
        }

        Text {
          Layout.fillWidth: true
          Layout.topMargin: 2
          visible: root.body.length > 0
          text: root.sanitizeBody(root.body)
          textFormat: Text.StyledText
          font.family: root.fontFamily
          color: root.bodyColor
          font.pixelSize: 13
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
    height: 3
    color: Color.notifications.border
    visible: false

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: parent.width * Math.max(0, Math.min(1, root.progress))
      color: root.accentColor
    }
  }
}
