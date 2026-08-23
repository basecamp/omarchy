import QtQuick
import Quickshell
import Quickshell.Io

// Agent Fabric minimum: catalog, permission, ledger, dispatch to typed providers.
// WindowService is the first provider. UI and agents share the same verbs.
QtObject {
  id: broker

  property var windowService: null
  property string home: Quickshell.env("HOME")
  property string ledgerPath: home + "/.local/state/omarchy/ultimate/capability-ledger.json"
  property var entries: []
  property var windowVerbs: ({
    close: ["address"],
    closeActive: [],
    minimize: ["address"],
    restore: ["address"],
    activate: ["address"],
    focus: ["address"],
    maximize: ["address"],
    unmaximize: ["address"],
    toggleMaximize: ["address"],
    restoreNormal: ["address"],
    snapLeft: ["address"],
    snapRight: ["address"],
    snapTo: ["address", "side"],
    snapArrow: ["address", "dir"],
    moveTo: ["address", "x", "y"],
    resizeTo: ["address", "w", "h"],
    saveLayout: [],
    restoreLayout: [],
    toggleShowDesktop: [],
    pin: ["desktopId"],
    unpin: ["desktopId"]
  })

  function catalog() {
    var window = []
    var name
    for (name in broker.windowVerbs) window.push(name)
    return { window: window }
  }

  function permit(actor, capability, verb) {
    if (capability !== "window")
      return { ok: false, title: "Unknown capability", explanation: "Only the window capability is registered.", detail: String(capability || "") }
    if (!broker.windowVerbs[verb])
      return { ok: false, title: "Unknown verb", explanation: "That window verb is not in the catalog.", detail: String(verb || "") }
    if (actor === "ipc" || actor === "ui" || actor === "agent" || actor === "undo" || !actor)
      return { ok: true }
    return { ok: false, title: "Permission denied", explanation: "This actor cannot call desktop capabilities.", detail: String(actor) }
  }

  function record(capability, verb, target, result, undo, actor) {
    var entry = {
      at: Date.now(),
      actor: String(actor || "ui"),
      capability: String(capability || ""),
      verb: String(verb || ""),
      target: String(target || ""),
      changed: !!(result && result.changed),
      error: result && result.error ? result.error : null,
      undo: undo || null
    }
    var next = broker.entries.slice()
    next.push(entry)
    if (next.length > 200) next = next.slice(next.length - 200)
    broker.entries = next
    ledgerFile.setText(JSON.stringify({ entries: next }, null, 2) + "\n")
    return entry
  }

  function invoke(capability, verb, args, actor) {
    args = args || {}
    var allowed = broker.permit(actor, capability, verb)
    if (!allowed.ok)
      return { changed: false, error: { title: allowed.title, explanation: allowed.explanation, detail: allowed.detail } }
    if (capability !== "window" || !broker.windowService)
      return { changed: false, error: { title: "No provider", explanation: "WindowService is not connected.", detail: "" } }
    var svc = broker.windowService
    var prev = svc._actor
    svc._actor = actor || "ipc"
    var result
    if (verb === "close") result = svc.close(args.address)
    else if (verb === "closeActive") result = svc.closeActive()
    else if (verb === "minimize") result = svc.minimize(args.address)
    else if (verb === "restore") result = svc.restore(args.address)
    else if (verb === "activate") result = svc.activate(args.address)
    else if (verb === "focus") result = svc.focus(args.address)
    else if (verb === "maximize") result = svc.maximize(args.address)
    else if (verb === "unmaximize") result = svc.unmaximize(args.address)
    else if (verb === "toggleMaximize") result = svc.toggleMaximize(args.address)
    else if (verb === "restoreNormal") result = svc.restoreNormal(args.address)
    else if (verb === "snapLeft") result = svc.snapLeft(args.address)
    else if (verb === "snapRight") result = svc.snapRight(args.address)
    else if (verb === "snapTo") result = svc.snapTo(args.address, args.side)
    else if (verb === "snapArrow") result = svc.snapArrow(args.address, args.dir)
    else if (verb === "moveTo") result = svc.moveTo(args.address, args.x, args.y)
    else if (verb === "resizeTo") result = svc.resizeTo(args.address, args.w, args.h)
    else if (verb === "saveLayout") result = svc.saveLayout()
    else if (verb === "restoreLayout") result = svc.restoreLayout()
    else if (verb === "toggleShowDesktop") result = svc.toggleShowDesktop()
    else if (verb === "pin") result = svc.pin({ id: args.desktopId, desktopId: args.desktopId })
    else if (verb === "unpin") result = svc.unpin(args.desktopId)
    else result = { changed: false, error: { title: "Unknown verb", explanation: "Not dispatched.", detail: verb } }
    svc._actor = prev || "ui"
    return result
  }

  function undoLast() {
    var i
    for (i = broker.entries.length - 1; i >= 0; i--) {
      var entry = broker.entries[i]
      if (!entry || !entry.changed || !entry.undo || !entry.undo.verb) continue
      return broker.invoke(entry.undo.capability || "window", entry.undo.verb, {
        address: entry.undo.address,
        side: entry.undo.side,
        dir: entry.undo.dir,
        desktopId: entry.undo.desktopId
      }, "undo")
    }
    return { changed: false, error: { title: "Nothing to undo", explanation: "The ledger has no invertible window operation.", detail: "" } }
  }

  property FileView ledgerFile: FileView {
    path: broker.ledgerPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        var parsed = JSON.parse(text() || "{}")
        broker.entries = Array.isArray(parsed.entries) ? parsed.entries : []
      } catch (e) {
        broker.entries = []
      }
    }
    onLoadFailed: broker.entries = []
    onFileChanged: reload()
  }
}
