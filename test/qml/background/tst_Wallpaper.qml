import QtQuick
import QtTest
import "../../../shell/plugins/background" as Background

TestCase {
  name: "WallpaperImage"
  when: windowShown
  width: 200
  height: 200

  Component { id: imageComponent; Background.WallpaperImage { asynchronous: true } }
  Component {
    id: observedImageComponent
    Background.WallpaperImage {
      asynchronous: true
      property int statusChanges: 0
      onStatusChanged: statusChanges++
    }
  }

  function test_fallback_data() {
    return [
      { tag: "missing", path: "missing.jpg" },
      { tag: "decode error", path: "invalid.svg" }
    ]
  }

  function test_fallback(data) {
    // The renderer adds its own status handler; inherited fallback must work too.
    var item = createTemporaryObject(observedImageComponent, this, {
      fallbackSource: Qt.resolvedUrl("theme.svg"),
      overrideSource: Qt.resolvedUrl(data.path)
    })
    verify(item)
    tryCompare(item, "status", Image.Ready)
    compare(item.source, Qt.resolvedUrl("theme.svg"))
    verify(item.statusChanges > 0)
    item.overrideSource = Qt.resolvedUrl("override %231.svg")
    tryCompare(item, "status", Image.Ready)
    compare(item.source, Qt.resolvedUrl("override %231.svg"))
  }

  function test_fixedOverride() {
    var item = createTemporaryObject(imageComponent, this, {
      fallbackSource: Qt.resolvedUrl("theme.svg"),
      overrideSource: Qt.resolvedUrl("override %231.svg")
    })
    tryCompare(item, "status", Image.Ready)
    var fixedSource = item.source
    item.fallbackSource = Qt.resolvedUrl("another-theme.svg")
    compare(item.source, fixedSource)
    compare(item.status, Image.Ready)
    item.fallbackSource = ""
    compare(item.status, Image.Null)
    item.fallbackSource = Qt.resolvedUrl("theme.svg")
    tryCompare(item, "status", Image.Ready)
    item.overrideSource = ""
    tryCompare(item, "status", Image.Ready)
    compare(item.source, Qt.resolvedUrl("theme.svg"))
  }
}
