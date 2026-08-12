import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Ui
import qs.Commons
import "KeyboardLayoutModel.js" as KeyboardLayoutModel

BarWidget {
  id: root
  moduleName: "omarchy.keyboard-layout"


  property string layoutFull: ""
  property string keyboardName: ""
  // Real keyboards on the seat, virtual ones excluded, and whether the last
  // reading left that shape in doubt.
  property int keyboardCount: 0
  property bool keyboardUnresolved: false
  // Nothing to read or switch on the single-layout install most people run, so
  // the widget ships on the bar and stays out of the way until there are two.
  // An older Hyprland that doesn't report the list keeps showing the label.
  property bool multipleLayouts: true
  // Short language code per layout description ("English (US)": "en"), read from
  // xkb's own table rather than maintained by hand.
  property var layoutBriefs: ({})
  readonly property string layoutLabel: KeyboardLayoutModel.shortLabel(layoutFull, layoutBriefs)

  // A query already in flight was started before this event, so it may read the
  // layout the switch replaced. Remember the request and re-run once it lands
  // rather than dropping it; nothing else would correct the label afterwards.
  property bool refreshPending: false

  function refresh() {
    if (queryProc.running) {
      refreshPending = true
      return
    }

    refreshPending = false
    queryProc.running = true
  }

  // fcitx5 binds a virtual keyboard and takes over the seat's main flag whenever
  // it injects, but that keyboard keeps the us layout the input method gave it.
  // Leave those out, so the label keeps tracking a keyboard someone types on.
  function typedKeyboards(keyboards) {
    return keyboards.filter(k => !String(k.name).startsWith("hl-virtual-keyboard"))
  }

  // The main flag names no keyboard for long: fcitx5 takes it with the virtual
  // keyboard it binds to inject, which leaves no typed keyboard holding it and
  // nothing to read at all, and once that unbinds it lands on whichever device
  // libinput listed last, as easily a lid switch as a keyboard. Go by layout
  // progress instead, and by the keyboard activelayout named.
  function selectKeyboard(typed) {
    return KeyboardLayoutModel.selectKeyboard(typed, root.keyboardName)
  }

  // switchxkblayout is a hyprctl command rather than a dispatcher, so it has to
  // be run rather than sent over the dispatch socket.
  function cycleLayout() {
    if (!root.keyboardName || !root.bar) return
    root.bar.run("hyprctl switchxkblayout " + Util.shellQuote(root.keyboardName) + " next")
    refreshTimer.restart()
  }

  Component.onCompleted: {
    briefsProc.running = true
    refresh()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || !event.name) return
      var name = String(event.name)
      // The event names the keyboard that switched ahead of the layout it moved
      // to, and that is the keyboard being typed on whatever holds the main flag.
      if (name === "activelayout") {
        var named = String(event.data || "").split(",")[0]
        if (named && !named.startsWith("hl-virtual-keyboard")) root.keyboardName = named
      }

      // A reload that edits kb_layout changes both the label and whether the
      // widget shows at all, and switches no layout, so it raises no
      // activelayout of its own.
      if (name.indexOf("activelayout") !== -1 || name === "configreloaded") root.refresh()
    }
  }

  Process {
    id: queryProc
    command: ["hyprctl", "-j", "devices"]
    onRunningChanged: {
      if (running) {
        stallTimer.restart()
        return
      }

      stallTimer.stop()
      if (root.refreshPending) root.refresh()
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        let typed
        try {
          typed = root.typedKeyboards(JSON.parse(text || "{}").keyboards ?? [])
        } catch (e) {
          return
        }

        const kb = root.selectKeyboard(typed)
        if (!kb || !kb.active_keymap) {
          // Keyboards are there but none of them answers to main, so the seat
          // just changed shape under an input method holding the flag. Say so,
          // rather than letting a count from before it changed settle the poll.
          if (typed.length > 0) root.keyboardUnresolved = true
          return
        }

        // A query the watchdog killed reports nothing at all, so only a reading
        // that named a keyboard gets to speak for the seat.
        root.keyboardUnresolved = false
        root.keyboardCount = typed.length
        root.multipleLayouts = kb.layout === undefined || String(kb.layout).indexOf(",") !== -1
        root.layoutFull = kb.active_keymap
      }
    }
  }

  // The table only changes when xkb data is upgraded, so read it at startup and
  // leave it alone. The bar is built per monitor, so this runs once per widget.
  // The exotic rulesets cover layouts like trans (IPA) that ship in the same xkb
  // package and set just as well, so load them or those labels lose their code.
  Process {
    id: briefsProc
    command: ["xkbcli", "list", "--load-exotic"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.layoutBriefs = KeyboardLayoutModel.layoutBriefs(text)
    }
  }

  Timer {
    id: refreshTimer
    interval: 600
    onTriggered: root.refresh()
  }

  // A query that never returns would freeze the label until the shell restarts,
  // since a Process that is already running can't be re-run. Give up on one that
  // overstays so the next refresh gets through.
  Timer {
    id: stallTimer
    interval: 5000
    onTriggered: queryProc.running = false
  }

  // Hyprland hands the seat's main flag to whichever keyboard was typed on last
  // and announces nothing when it moves, so a seat holding more than one keyboard
  // can only learn which one the label is describing by asking. Poll while there
  // is that ambiguity, until a first reading lands so a query that failed at login
  // still recovers, and while a reading has left the seat's shape in doubt. The
  // one-keyboard install has none of those, and is left alone rather than spawning
  // hyprctl forever for an answer that cannot change.
  Timer {
    interval: 10000
    running: !root.keyboardName || root.keyboardUnresolved || root.keyboardCount > 1
    repeat: true
    onTriggered: root.refresh()
  }

  visible: layoutLabel !== "" && multipleLayouts
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.layoutLabel
    fontSize: Style.font.caption
    horizontalMargin: 6
    tooltipText: root.layoutFull
    onPressed: function() { root.cycleLayout() }
  }
}
