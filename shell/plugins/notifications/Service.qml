// Notification service for the omarchy shell.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications
import qs.Commons

import "components"
import "NotificationLogic.js" as NotificationLogic

Item {
  id: service

  // Injected by omarchy-shell (the first-party service loader).
  property var shell: null

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  readonly property string home: Quickshell.env("HOME")
  // History + DND live under XDG_STATE_HOME: they're persistent user state
  // (history of received notifications, last-set DND preference), not
  // regeneratable cache that a `rm -rf ~/.cache` should wipe.
  readonly property string stateDir: home + "/.local/state/omarchy/"
  readonly property string historyPath: stateDir + "notifications.json"
  // Thumbnails copied from /tmp screenshots are genuinely disposable — if
  // they vanish the row just renders without an image — so they stay in
  // ~/.cache where regeneratable artifacts belong.
  readonly property string cacheDir: home + "/.cache/omarchy/"
  readonly property string imageCacheDir: cacheDir + "notification-images/"
  // Corner radius is shared with the menu and bar settings panel.
  // It mirrors Hyprland's current decoration:rounding value.
  readonly property int cornerRadius: Style.cornerRadius
  // Surfaces anchor relative to the omarchy bar so popups and history land
  // alongside the other shell panels rather than on top of the bar itself.
  // Falls back to the bar's default size (26 horizontal / 28 vertical) when
  // shell.bar isn't reachable so the popup never lands on top of the bar.
  readonly property string barPosition: shell && shell.barConfig ? String(shell.barConfig.position || "top") : "top"
  readonly property bool barVertical: barPosition === "left" || barPosition === "right"
  readonly property int defaultBarSize: barVertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal
  readonly property int liveBarSize: shell && shell.bar && !shell.bar.barHidden ? Math.max(0, shell.bar.barSize) : defaultBarSize
  readonly property int barClearance: liveBarSize + Style.gapsOut

  // Fired by IPC (`omarchy-shell notifications showHistory`) so the
  // bar widget can drop its PopupCard from the same anchor a click would.
  signal historyOpenRequested()

  // PersistentProperties handles in-process QML reloads. The on-disk
  // notifications.json file is the cross-restart backstop — its `dnd` key
  // is hydrated into persisted.doNotDisturb on startup and written back via
  // the same debounced save timer used for history entries.
  PersistentProperties {
    id: persisted
    reloadableId: "omarchy-notifications"
    property bool doNotDisturb: false
    onDoNotDisturbChanged: {
      // Suppress the write that load-time hydration would otherwise trigger.
      if (service._hydrating) return
      service.scheduleHistorySave()
    }
  }

  // Guards onDoNotDisturbChanged while we're hydrating from disk so the
  // hydration assignment doesn't immediately schedule a write-back.
  property bool _hydrating: false

  readonly property alias doNotDisturb: persisted.doNotDisturb

  function setDoNotDisturb(value) {
    persisted.doNotDisturb = !!value
  }

  // popupModel feeds the on-screen toast stack.
  // pendingModel  = notifications received but not yet "seen" by the user.
  //                 Anything DND-suppressed lands here and stays there until
  //                 the user reviews it; anything that pops up also lives
  //                 here until the popup dismisses, then moves to pastModel.
  // pastModel     = notifications the user has already seen on-screen.
  //                 Surfaced under the Past tab in the history panel.
  //
  // Aliased as properties so the bar widget and HistoryPanel (outside this
  // Item's id scope) can bind to them. QML ids aren't visible to external
  // consumers without the alias.
  property alias popupModel: popupModel
  property alias pendingModel: pendingModel
  property alias pastModel: pastModel
  ListModel { id: popupModel }
  ListModel { id: pendingModel }
  ListModel { id: pastModel }

  readonly property int historyCap: 100
  property var imageCacheQueue: []

  readonly property int lowPopupDuration: 5000
  readonly property int normalPopupDuration: 8000
  readonly property int maxPopupDuration: 30000

  function durationFor(urgency, expireTimeout) {
    switch (urgency) {
    case NotificationUrgency.Critical:
      return 0
    case NotificationUrgency.Low:
      return Math.min(maxPopupDuration, Math.max(lowPopupDuration, requestedDuration(expireTimeout)))
    default:
      return Math.min(maxPopupDuration, Math.max(normalPopupDuration, requestedDuration(expireTimeout)))
    }
  }

  function requestedDuration(expireTimeout) {
    var seconds = Number(expireTimeout || 0)
    if (!isFinite(seconds) || seconds <= 0) return 0
    return Math.round(seconds * 1000)
  }

  // DND bypass: only let through notifications we trust to be intentional
  // and rare.
  //   - omarchy-action: a user-action confirmation toast ("Theme changed",
  //     "Screenshot saved"). The user JUST did something — their feedback
  //     should show.
  //   - urgency=critical AND app_name=notify-send: bare-CLI emergency alerts.
  //     Trusted because it's almost always omarchy or system shell scripts —
  //     chat apps set app_name to their brand (Discord/Slack/Vesktop), which
  //     falls outside this rule.
  function shouldBypassDnd(notification) {
    return NotificationLogic.shouldBypassDnd(notification, NotificationUrgency.Critical)
  }

  function snapshotOf(notification) {
    return NotificationLogic.snapshotOf(notification, Date.now())
  }

  function handleNotification(notification) {
    // Without `tracked = true` the Notification object is destroyed as soon
    // as this signal handler returns, which would null out the `ref` we just
    // captured for the popup card.
    notification.tracked = true
    var snapshot = snapshotOf(notification)
    // History is for notifications from real apps (Slack, Discord, mailer,
    // etc.) — things the user might want to look back at. Skip the pending
    // / past bookkeeping when:
    //   - the freedesktop `transient` hint is set ("popup only, don't store")
    //   - app_name is "notify-send" (the CLI default — means the sender
    //     didn't bother declaring an identity, so it's almost certainly
    //     ephemeral test/feedback noise)
    //   - app_name is "omarchy-action" (Omarchy's own user-action
    //     toasts — the user just triggered them, they don't
    //     need to be archived)
    var transient = false
    try {
      transient = !!(notification.hints && notification.hints["transient"])
    } catch (e) { transient = false }
    var appName = String(notification.appName || "")
    var ephemeralApp = NotificationLogic.isEphemeralApp(appName)
    if (transient || ephemeralApp) {
      if (service.doNotDisturb && !shouldBypassDnd(notification)) {
        notification.tracked = false
        return
      }
      Qt.callLater(function() {
        removeByOriginalId(popupModel, snapshot.originalId)
        popupModel.insert(0, snapshot)
      })
      return
    }

    // Pending first, unconditionally. DND only suppresses the toast — the
    // record still has to land somewhere the user can review later.
    addToPending(snapshot)

    // Kick off a copy of any /tmp screenshot into the persistent image cache.
    // The cp races the popup; the popup keeps the original path so it always
    // renders, and the history row gets rewritten to the cached path once
    // cp.exits.
    maybeCacheImage(snapshot)

    // DND bypass rules — see ~/Work/omarchy/dnd-fix-plan.md. The pending
    // entry already captured this notification above; we just decide here
    // whether to also pop a toast. Chat apps abuse urgency=critical to
    // force visibility, so critical alone isn't enough — we also require
    // the sender to be CLI-style. See shouldBypassDnd().
    if (service.doNotDisturb && !shouldBypassDnd(notification)) {
      notification.tracked = false
      return
    }

    // Qt.callLater avoids "QV4::Object::insertMember" crashes when a
    // Repeater is mid-incubation while we mutate its model.
    Qt.callLater(function() {
      removeByOriginalId(popupModel, snapshot.originalId)
      popupModel.insert(0, snapshot)
    })
  }

  // Remove every row in `model` whose originalId matches. Chat apps reuse
  // `replaces_id` per the freedesktop spec to update a single notification
  // in place — without this, every Discord/Slack ping leaves a fresh row
  // behind and pending fills with hundreds of duplicates.
  function removeByOriginalId(model, originalId) {
    for (var i = model.count - 1; i >= 0; i--) {
      var row = model.get(i)
      if (row && row.originalId === originalId) model.remove(i)
    }
  }

  function addToPending(snapshot) {
    Qt.callLater(function() {
      removeByOriginalId(pendingModel, snapshot.originalId)
      pendingModel.insert(0, snapshot)
      while (pendingModel.count > service.historyCap) {
        pendingModel.remove(pendingModel.count - 1)
      }
      scheduleHistorySave()
    })
  }

  // Find a pending entry by its libnotify id and move it to pastModel. Called
  // when a popup naturally dismisses (timer expired or user clicked X / the
  // default action) — the user is assumed to have seen it.
  function markSeenByOriginalId(originalId) {
    Qt.callLater(function() {
      for (var i = 0; i < pendingModel.count; i++) {
        var entry = pendingModel.get(i)
        if (!entry || entry.originalId !== originalId) continue
        var snapshot = service.snapshotFromRow(entry)
        pendingModel.remove(i)
        pastModel.insert(0, snapshot)
        while (pastModel.count > service.historyCap) {
          pastModel.remove(pastModel.count - 1)
        }
        scheduleHistorySave()
        return
      }
    })
  }

  // Copy a ListModel row into a plain JS object so we can re-insert it into
  // a different model without sharing references.
  function snapshotFromRow(row) {
    return {
      id: row.id,
      originalId: row.originalId,
      app: row.app,
      appIcon: row.appIcon,
      summary: row.summary,
      body: row.body,
      image: row.image,
      glyph: row.glyph || "",
      urgency: row.urgency,
      expireTimeout: row.expireTimeout || 0,
      timestamp: row.timestamp
    }
  }

  function markAllSeen() {
    Qt.callLater(function() {
      while (pendingModel.count > 0) {
        var entry = pendingModel.get(0)
        var snapshot = service.snapshotFromRow(entry)
        pendingModel.remove(0)
        pastModel.insert(0, snapshot)
      }
      while (pastModel.count > service.historyCap) {
        pastModel.remove(pastModel.count - 1)
      }
      scheduleHistorySave()
    })
  }

  function dismissPopup(index) {
    removePopup(index, "dismiss")
  }

  function expirePopup(index) {
    removePopup(index, "expire")
  }

  function removePopup(index, reason) {
    if (index < 0 || index >= popupModel.count) return
    var entry = popupModel.get(index)
    var ref = entry ? entry.ref : null
    var originalId = entry ? entry.originalId : -1
    popupModel.remove(index)
    if (ref) {
      try {
        if (ref.tracked) {
          if (reason === "expire" && typeof ref.expire === "function") ref.expire()
          else ref.dismiss()
        }
      } catch (e) {
        // Object already torn down by the server — nothing to dismiss.
      }
    }
    // User (or the lifetime timer) saw the popup — archive it.
    if (originalId >= 0) markSeenByOriginalId(originalId)
  }

  function clearPopups() {
    while (popupModel.count > 0) dismissPopup(0)
  }

  function dismissPending(index) {
    if (index < 0 || index >= pendingModel.count) return
    var entry = pendingModel.get(index)
    if (entry) maybeDeleteCachedImage(entry.image)
    pendingModel.remove(index)
    scheduleHistorySave()
  }

  function dismissPast(index) {
    if (index < 0 || index >= pastModel.count) return
    var entry = pastModel.get(index)
    if (entry) maybeDeleteCachedImage(entry.image)
    pastModel.remove(index)
    scheduleHistorySave()
  }

  function clearPending() {
    for (var i = 0; i < pendingModel.count; i++) {
      var entry = pendingModel.get(i)
      if (entry) maybeDeleteCachedImage(entry.image)
    }
    pendingModel.clear()
    scheduleHistorySave()
  }

  function clearPast() {
    for (var i = 0; i < pastModel.count; i++) {
      var entry = pastModel.get(i)
      if (entry) maybeDeleteCachedImage(entry.image)
    }
    pastModel.clear()
    scheduleHistorySave()
  }

  // Invoke the libnotify "default" action on the popup's underlying
  // notification, if it has one, then dismiss. Clients register the default
  // action with the canonical identifier "default"; e.g. screenshot toasts
  // use `notify-send -A default=Edit ...` so click-the-card opens the editor.
  function invokePopupDefault(index) {
    if (index < 0 || index >= popupModel.count) return
    var entry = popupModel.get(index)
    var ref = entry ? entry.ref : null
    var invoked = false
    if (ref && ref.actions) {
      for (var i = 0; i < ref.actions.length; i++) {
        var action = ref.actions[i]
        if (action && action.identifier === "default") {
          try { action.invoke(); invoked = true } catch (e) { console.warn("invoke default failed:", e) }
          break
        }
      }
    }
    // Chat apps (Slack, Discord, Vesktop, etc.) rarely register a "default"
    // libnotify action — they just expect clicking the notification to
    // focus their window. Fall back to focusing the sending app by class so
    // that click-to-jump actually works.
    if (!invoked) focusApp(entry)
    dismissPopup(index)
  }

  // Try to focus an existing Hyprland window matching the notification's
  // sender. The helper handles case-insensitive class matching.
  function focusApp(entry) {
    if (!entry || !entry.app) return
    focusAppProc.command = [
      service.omarchyPath + "/bin/omarchy-hyprland-focus-app",
      String(entry.app)
    ]
    focusAppProc.running = true
  }

  Process { id: focusAppProc; running: false }

  // ---------------------------------------------------- image cache
  //
  // Notifications coming from screenshot helpers ship an `image-path` hint
  // pointing at /tmp/<file>. We want the history thumbnail to outlive that
  // file, so we copy it into a long-lived cache dir on ingress and rewrite
  // the history row's `image` to point at the cache once cp finishes.
  // image:// (raw-bytes) URIs aren't trivially copyable from QML; document
  // and skip them for v1.

  function imageExtension(srcPath) {
    return NotificationLogic.imageExtension(srcPath)
  }

  function maybeCacheImage(snapshot) {
    var image = String(snapshot.image || "")
    if (!image) return
    // image:// URIs are decoded from raw bytes by Quickshell's image provider.
    // We can't copy them out from QML, so let history reference them by URI
    // and accept that they disappear with the source notification.
    if (image.indexOf("image://") === 0) return
    if (image.indexOf("file:///tmp/") !== 0) return

    var srcPath = decodeURIComponent(image.substring(7))
    var ext = imageExtension(srcPath)
    var destPath = imageCacheDir + snapshot.timestamp + "-" + snapshot.originalId + "." + ext
    var destUri = Util.fileUrl(destPath)

    imageCacheQueue = imageCacheQueue.concat([{
      srcPath: srcPath,
      destPath: destPath,
      targetUri: destUri,
      originalId: snapshot.originalId,
      timestamp: snapshot.timestamp
    }])
    runNextImageCacheJob()
  }

  function runNextImageCacheJob() {
    if (imageCacheProc.running || imageCacheQueue.length === 0) return

    var job = imageCacheQueue[0]
    imageCacheQueue = imageCacheQueue.slice(1)
    imageCacheProc.targetUri = job.targetUri
    imageCacheProc.matchOriginalId = job.originalId
    imageCacheProc.matchTimestamp = job.timestamp
    imageCacheProc.command = ["cp", "-f", job.srcPath, job.destPath]
    imageCacheProc.running = true
  }

  function rewriteCachedImage(targetUri, originalId, timestamp) {
    function rewrite(model) {
      for (var i = 0; i < model.count; i++) {
        var row = model.get(i)
        if (row && row.originalId === originalId && row.timestamp === timestamp) {
          model.setProperty(i, "image", targetUri)
          return true
        }
      }
      return false
    }

    return rewrite(pendingModel) || rewrite(pastModel)
  }

  function maybeDeleteCachedImage(image) {
    var path = String(image || "")
    if (!path) return
    if (path.indexOf("file://") !== 0) return
    var local = decodeURIComponent(path.substring(7))
    if (local.indexOf(imageCacheDir) !== 0) return
    deleteImageProc.command = ["rm", "-f", local]
    deleteImageProc.running = true
  }

  Process {
    id: ensureDirsProc
    command: ["mkdir", "-p", service.stateDir, service.imageCacheDir]
    running: false
  }

  Process {
    id: imageCacheProc
    property string targetUri: ""
    property int matchOriginalId: -1
    property double matchTimestamp: 0
    onExited: function(exitCode) {
      if (exitCode === 0 && targetUri && rewriteCachedImage(targetUri, matchOriginalId, matchTimestamp))
        scheduleHistorySave()
      targetUri = ""
      matchOriginalId = -1
      matchTimestamp = 0
      runNextImageCacheJob()
    }
  }

  Process { id: deleteImageProc; running: false }

  // ---------------------------------------------------- history persistence

  FileView {
    id: historyFile
    path: service.historyPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: service.loadHistory(text())
    // First-run: the file doesn't exist yet. Without this branch,
    // `historyLoaded` stays false forever and `scheduleHistorySave` becomes
    // a no-op — so the file is never created and history vanishes on
    // shell restart.
    onLoadFailed: service.loadHistory("")
  }

  Timer {
    id: historySaveTimer
    interval: 200
    repeat: false
    onTriggered: service.flushHistory()
  }

  // Past is a rolling "recently" window. Sweep every minute and drop
  // anything older than 15 minutes so the tab doesn't accumulate forever.
  readonly property int pastTtlMs: 15 * 60 * 1000

  Timer {
    id: pastPruneTimer
    interval: 60 * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: service.prunePast()
  }

  function prunePast() {
    if (pastModel.count === 0) return
    var cutoff = Date.now() - service.pastTtlMs
    var removed = false
    for (var i = pastModel.count - 1; i >= 0; i--) {
      var entry = pastModel.get(i)
      if (entry && entry.timestamp && entry.timestamp < cutoff) {
        if (entry.image) maybeDeleteCachedImage(entry.image)
        pastModel.remove(i)
        removed = true
      }
    }
    if (removed) scheduleHistorySave()
  }

  function scheduleHistorySave() {
    if (!service.historyLoaded) return
    historySaveTimer.restart()
  }

  property bool historyLoaded: false

  function loadHistory(raw) {
    // FileView can fire onLoaded more than once during startup — the implicit
    // preload when `path` resolves, plus the explicit `historyFile.reload()`
    // in Component.onCompleted can both end up calling here. Without this
    // guard, the second fire appends a second copy of every persisted row
    // to the in-memory model.
    if (service.historyLoaded) return

    var parsed = NotificationLogic.parseHistory(raw, NotificationUrgency.Normal, service.historyCap)
    if (parsed.empty) {
      service.historyLoaded = true
      return
    }
    if (parsed.error) {
      console.warn("notifications: history parse failed:", parsed.errorMessage || "")
      service.historyLoaded = true
      return
    }

    if (parsed.dnd !== null) {
      service._hydrating = true
      persisted.doNotDisturb = parsed.dnd
      service._hydrating = false
    }

    // Newest-first on disk; append in order so models match.
    Qt.callLater(function() {
      for (var i = 0; i < parsed.pending.length; i++) pendingModel.append(parsed.pending[i])
      for (var j = 0; j < parsed.past.length; j++) pastModel.append(parsed.past[j])
      service.historyLoaded = true
      if (parsed.hadDuplicates) service.scheduleHistorySave()
    })
  }

  function flushHistory() {
    function dump(model) {
      var out = []
      for (var i = 0; i < model.count; i++) {
        var r = model.get(i)
        if (!r) continue
        out.push({
          id: r.id,
          originalId: r.originalId,
          app: r.app,
          appIcon: r.appIcon,
          summary: r.summary,
          body: r.body,
          image: r.image,
          glyph: r.glyph || "",
          urgency: r.urgency,
          expireTimeout: r.expireTimeout || 0,
          timestamp: r.timestamp
        })
      }
      return out
    }
    var payload = {
      version: 2,
      dnd: persisted.doNotDisturb,
      pending: dump(pendingModel),
      past: dump(pastModel)
    }
    historyFile.setText(JSON.stringify(payload, null, 2) + "\n")
  }

  Component.onCompleted: {
    ensureDirsProc.running = true
    // Once mkdir has had a tick, load the existing history file. FileView
    // surfaces an empty string when the file doesn't exist; loadHistory
    // handles that path.
    Qt.callLater(function() { historyFile.reload() })
  }

  // ---------------------------------------------------- IPC

  IpcHandler {
    target: "notifications"

    function dndState(): string {
      return service.doNotDisturb ? "on" : "off"
    }

    function toggleDnd(): string {
      service.setDoNotDisturb(!service.doNotDisturb)
      return dndState()
    }

    function setDnd(value: string): string {
      var v = String(value || "").toLowerCase()
      var on = v === "true" || v === "1" || v === "on" || v === "yes"
      service.setDoNotDisturb(on)
      return dndState()
    }

    function isDnd(): string {
      return dndState()
    }

    function showHistory(): string {
      service.historyOpenRequested()
      return "ok"
    }

    // `clear` empties the past tab (the "I already saw these" bucket).
    function clear(): string {
      service.clearPast()
      return "ok"
    }

    function clearPending(): string {
      service.clearPending()
      return "ok"
    }

    function markAllSeen(): string {
      service.markAllSeen()
      return "ok"
    }

    function dismissAll(): string {
      service.clearPopups()
      service.clearPending()
      service.clearPast()
      return "ok"
    }

    // dismiss the most recent popup; fall back to the most recent pending
    // entry, then past, if no popup is currently showing.
    function dismissOne(): string {
      if (popupModel.count > 0) {
        service.dismissPopup(0)
        return "ok"
      }
      if (pendingModel.count > 0) {
        service.dismissPending(0)
        return "ok"
      }
      if (pastModel.count > 0) {
        service.dismissPast(0)
        return "ok"
      }
      return "none"
    }

    // Fire the default action on the most recent popup, then dismiss it.
    function invokeLast(): string {
      if (popupModel.count === 0) return "none"
      service.invokePopupDefault(0)
      return "ok"
    }

    function dismiss(summary: string): string {
      var needle = String(summary || "")
      if (!needle) return "none"
      var hit = false
      function sweep(model, dismissFn) {
        for (var i = model.count - 1; i >= 0; i--) {
          var row = model.get(i)
          if (row && String(row.summary || "").indexOf(needle) !== -1) {
            dismissFn(i)
            hit = true
          }
        }
      }
      sweep(pendingModel, service.dismissPending)
      sweep(pastModel, service.dismissPast)
      sweep(popupModel, service.dismissPopup)
      return hit ? "ok" : "none"
    }

    function ping(): string { return "ok" }
  }

  // ---------------------------------------------------- server

  NotificationServer {
    id: server
    keepOnReload: false
    imageSupported: true
    actionsSupported: true
    bodyMarkupSupported: true
    bodyHyperlinksSupported: true
    persistenceSupported: true

    onNotification: function(notification) {
      service.handleNotification(notification)
    }
  }

  // -------------------------------------------------------------- popup UI
  //
  // One PanelWindow per output (Variants on Quickshell.screens) holding the
  // stacked toast cards. Layer is Overlay, exclusionMode Ignore, no
  // keyboard focus — popups are passive surfaces and must never steal input
  // from the focused application.

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: popupWindow
      required property var modelData
      screen: modelData
      visible: popupModel.count > 0

      WlrLayershell.namespace: "omarchy-notifications"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"

      anchors {
        top: service.barPosition !== "bottom"
        bottom: service.barPosition === "bottom"
        left: service.barPosition === "left"
        right: service.barPosition !== "left"
      }
      margins {
        top:    service.barPosition === "top"    ? service.barClearance : Style.gapsOut
        bottom: service.barPosition === "bottom" ? service.barClearance : Style.gapsOut
        left:   service.barPosition === "left"   ? service.barClearance : Style.gapsOut
        right:  service.barPosition === "right"  ? service.barClearance : Style.gapsOut
      }

      implicitWidth: popupColumn.implicitWidth
      implicitHeight: popupColumn.implicitHeight

      ColumnLayout {
        id: popupColumn
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(8)

        Repeater {
          model: popupModel

          // The delegate is a slot Item that owns lifetime timer state. The
          // actual visuals live in NotificationCard, which the history panel
          // also reuses.
          delegate: Item {
            id: cardSlot
            required property int index
            required property string app
            required property string appIcon
            required property string summary
            required property string body
            required property string image
            required property string glyph
            required property int urgency
            required property double expireTimeout
            required property double timestamp

            // Each card sizes itself based on mode (text vs media); the slot
            // tracks the card so the column auto-fits to whichever is widest.
            Layout.preferredWidth: card.implicitWidth
            Layout.alignment: Qt.AlignRight
            implicitHeight: card.implicitHeight

            readonly property real lifetime: service.durationFor(cardSlot.urgency, cardSlot.expireTimeout)
            property real remainingLifetime: 1.0
            readonly property bool ticking: cardSlot.lifetime > 0 && !card.hovered

            Timer {
              interval: 50
              repeat: true
              running: cardSlot.ticking
              onTriggered: {
                if (cardSlot.lifetime <= 0) return
                cardSlot.remainingLifetime -= 50.0 / cardSlot.lifetime
                if (cardSlot.remainingLifetime <= 0) {
                  cardSlot.remainingLifetime = 0
                  service.expirePopup(cardSlot.index)
                }
              }
            }

            NotificationCard {
              id: card
              anchors.right: parent.right
              app: cardSlot.app
              appIcon: cardSlot.appIcon
              summary: cardSlot.summary
              body: cardSlot.body
              image: cardSlot.image
              urgency: cardSlot.urgency
              timestamp: cardSlot.timestamp
              cornerRadius: service.cornerRadius
              fontFamily: service.shell && service.shell.bar ? service.shell.bar.fontFamily : ""
              glyph: cardSlot.glyph

              onCloseRequested: service.dismissPopup(cardSlot.index)
              onCardClicked: service.invokePopupDefault(cardSlot.index)
            }
          }
        }
      }
    }
  }
}
