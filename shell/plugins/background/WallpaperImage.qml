import QtQuick

Image {
  id: root

  property url overrideSource: ""
  property url fallbackSource: ""
  property url rejectedSource: ""

  // Keep empty transition layers empty. Decode failures include missing and
  // unreadable files, and must fall back to this layer's theme image.
  source: fallbackSource.toString() ? (overrideSource.toString() && rejectedSource !== overrideSource ? overrideSource : fallbackSource) : ""
  onOverrideSourceChanged: rejectedSource = ""
  onStatusChanged: {
    if (status === Image.Error && overrideSource.toString() && rejectedSource !== overrideSource)
      rejectedSource = overrideSource
  }
}
