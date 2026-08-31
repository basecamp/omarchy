import QtQuick
import qs.Commons

// Wallpaper surface shared by the background and lock plugins. Renders one
// image with the fill mode, fill color, and crop focal point published by
// BackgroundResolver. The default configuration (crop, centered focal, no
// source-size cap) renders exactly like a bare PreserveAspectCrop Image.
Item {
  id: root

  property string path: ""
  property string fill: "crop"
  property color fillColor: Color.background
  property real focalX: 0.5
  property real focalY: 0.5
  // Lock cache-busting: appended as ?v= when > 0 so Image reloads a changed
  // background mid-session without a path change.
  property int sourceVersion: 0
  // Lock parity: decode at the view's physical pixel size instead of the
  // image's natural size.
  property bool useSourceSizeCap: false

  property alias asynchronous: image.asynchronous
  property alias cache: image.cache
  property alias smooth: image.smooth
  property alias mipmap: image.mipmap
  readonly property alias status: image.status

  readonly property bool centeredFocal: Math.abs(focalX - 0.5) < 0.001 && Math.abs(focalY - 0.5) < 0.001
  // PreserveAspectCrop always crops around the center, so a non-center focal
  // needs a manual crop window: size the image to its cover dimensions and
  // slide it so the focal fraction of the overflow is cropped away.
  readonly property bool manualCrop: fill === "crop" && !centeredFocal

  clip: manualCrop || fill === "center"

  Rectangle {
    anchors.fill: parent
    color: root.fillColor
    visible: root.fill !== "crop"
  }

  Image {
    id: image

    readonly property bool coverReady: root.manualCrop && status === Image.Ready && implicitWidth > 0 && implicitHeight > 0
    readonly property real coverScale: coverReady ? Math.max(root.width / implicitWidth, root.height / implicitHeight) : 1

    readonly property int physWidth: Math.round(root.width * Screen.devicePixelRatio)
    readonly property int physHeight: Math.round(root.height * Screen.devicePixelRatio)
    // center and tile paint 1:1 like the uncapped desktop, so the cap never
    // applies to them; capping would scale a large image down to fit.
    readonly property bool capActive: root.useSourceSizeCap && root.fill !== "center" && root.fill !== "tile"
    // The image's natural aspect, learned from the first decode (which
    // preserves it even when scaled). It lets the manual-crop path re-request
    // its decode at the exact cover size — the plain cap decodes fit-WITHIN
    // the view, and upscaling that by coverScale is visibly blurry.
    property real naturalAspect: 0

    onSourceChanged: naturalAspect = 0
    onStatusChanged: {
      if (status === Image.Ready && naturalAspect === 0 && implicitWidth > 0 && implicitHeight > 0)
        naturalAspect = implicitWidth / implicitHeight
    }

    source: root.path ? Util.fileUrl(root.path) + (root.sourceVersion > 0 ? "?v=" + root.sourceVersion : "") : ""
    fillMode: {
      if (root.manualCrop) return Image.Stretch
      if (root.fill === "fit") return Image.PreserveAspectFit
      if (root.fill === "center") return Image.Pad
      if (root.fill === "tile") return Image.Tile
      return Image.PreserveAspectCrop
    }
    asynchronous: true
    // A 0 dimension leaves the decode at the image's natural size. The cap is
    // in physical pixels — a logical-size decode leaves the wallpaper blurry
    // on HiDPI displays. PreserveAspectCrop and PreserveAspectFit give the
    // decoder the right scaling hint on their own; the manual focal crop
    // renders through Stretch, so it computes the cover dimensions itself
    // once the aspect is known.
    sourceSize.width: {
      if (!image.capActive) return 0
      if (root.manualCrop && image.naturalAspect > 0 && image.physHeight > 0)
        return image.naturalAspect > image.physWidth / image.physHeight ? Math.round(image.physHeight * image.naturalAspect) : image.physWidth
      return image.physWidth
    }
    sourceSize.height: {
      if (!image.capActive) return 0
      if (root.manualCrop && image.naturalAspect > 0 && image.physHeight > 0)
        return image.naturalAspect > image.physWidth / image.physHeight ? image.physHeight : Math.round(image.physWidth / image.naturalAspect)
      return image.physHeight
    }

    width: coverReady ? implicitWidth * coverScale : root.width
    height: coverReady ? implicitHeight * coverScale : root.height
    x: coverReady ? -(width - root.width) * Util.clamp(root.focalX, 0, 1) : 0
    y: coverReady ? -(height - root.height) * Util.clamp(root.focalY, 0, 1) : 0
  }
}
