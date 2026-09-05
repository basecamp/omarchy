// Captures in-process image:// URLs into files under the notification state
// dir. An image-data hint only exists as pixels served by the live
// Notification object's image provider — there is no file to copy, and the
// pixels die with the sender. Rendering the URL into an Image and grabbing
// the result is the only way to keep them.
//
// grabToImage needs its item attached to a mapped window, and a DND-silenced
// notification never puts one on screen — so captures run inside a 1x1
// transparent overlay surface that maps only while a grab is pending.

import QtQuick
import Quickshell
import Quickshell.Wayland

Item {
  id: capture

  // Pending {url, to, done} jobs. One at a time: a single Image is the
  // render source, and each grab must finish before its source changes.
  property var queue: []
  property var current: null

  // Largest edge a capture keeps. Avatars are small; a hostile sender must
  // not be able to park a wall-sized image in the state dir.
  readonly property int maxDimension: 512

  function request(url, to, done) {
    queue.push({ url: String(url || ""), to: String(to || ""), done: done || null })
    pump()
  }

  function pump() {
    if (current || queue.length === 0) return
    current = queue.shift()
    grabber.source = current.url
    deadline.restart()
    attempt()
  }

  // Runs on every state change that could unblock the grab: the image loads,
  // the surface maps. grabToImage fails until the window is mapped and has
  // rendered, so a false start just retries until the deadline gives up.
  function attempt() {
    if (!capture.current) return
    if (grabber.status === Image.Error) {
      finish(false)
      return
    }
    if (grabber.status !== Image.Ready) return
    var w = Math.max(1, grabber.implicitWidth)
    var h = Math.max(1, grabber.implicitHeight)
    var scale = Math.min(1, maxDimension / Math.max(w, h))
    var job = capture.current
    var started = grabber.grabToImage(function(result) {
      if (capture.current !== job) return
      capture.finish(result.saveToFile(job.to))
    }, Qt.size(Math.max(1, Math.round(w * scale)), Math.max(1, Math.round(h * scale))))
    if (!started) retry.restart()
  }

  function finish(ok) {
    var job = current
    if (!job) return
    current = null
    grabber.source = ""
    deadline.stop()
    retry.stop()
    if (job.done) {
      try {
        job.done(!!ok)
      } catch (e) {
        console.warn("notifications: capture callback failed:", e)
      }
    }
    pump()
  }

  Timer {
    id: retry
    interval: 100
    onTriggered: capture.attempt()
  }

  // A sender can die mid-grab (its provider then never loads) — give up so
  // the queue moves on; the entry's card falls back to the app icon.
  Timer {
    id: deadline
    interval: 3000
    onTriggered: capture.finish(false)
  }

  PanelWindow {
    visible: capture.current !== null
    WlrLayershell.namespace: "omarchy-notification-capture"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    implicitWidth: 1
    implicitHeight: 1
    anchors { top: true; left: true }
    mask: Region {}

    Image {
      id: grabber
      // Off the 1x1 surface: the grab renders the item into its own buffer,
      // so the image itself must never paint on screen.
      x: 4
      y: 4
      cache: false
      asynchronous: true
      onStatusChanged: capture.attempt()
    }
  }
}
