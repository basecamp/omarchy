import QtQuick
import Quickshell

// Drives the agents Main.qml through the account-identity paths: records that
// carry a mark, snapshots that carry it across machines, and the refusal to
// pool two tools that happen to share an account name.
ShellRoot {
  id: root

  readonly property string resultPath: Quickshell.env("OMARCHY_QML_TEST_RESULT")
  property var failures: []

  function fail(message) {
    failures.push(String(message))
  }

  function assertTrue(condition, message) {
    if (!condition) fail(message)
  }

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function writeResult() {
    var payload = JSON.stringify({ ok: failures.length === 0, failures: failures })
    if (resultPath)
      Quickshell.execDetached(["bash", "-lc", "printf '%s' " + shellQuote(payload) + " > " + shellQuote(resultPath)])
  }

  // An explicit file:// url, not a bare path: a path goes through Quickshell's
  // own vfs, where Main.qml's sibling Agent.qml no longer resolves.
  Loader {
    id: usage
    source: "file://" + Quickshell.env("OMARCHY_PATH") + "/shell/plugins/agents/Main.qml"
  }

  function recordsLoaded() {
    var agents = usage.item ? usage.item.agents : []
    if (agents.length !== 2) return false
    for (var i = 0; i < agents.length; i++)
      if (!agents[i] || !agents[i].record) return false
    return true
  }

  function recordById(id) {
    var agents = usage.item.agents
    for (var i = 0; i < agents.length; i++)
      if (agents[i].record && String(agents[i].record.id) === id) return agents[i].record
    return null
  }

  Timer {
    interval: 120
    repeat: true
    running: true
    property int ticks: 0

    onTriggered: {
      ticks++
      if (!usage.item || !root.recordsLoaded()) {
        if (ticks > 60) {
          root.fail("usage records for both accounts load")
          running = false
          root.writeResult()
        }
        return
      }
      running = false

      var item = usage.item

      // The mark travels from the record into the display object the panel
      // reads, so a second account of one tool wears that tool's icon.
      var work = root.recordById("claude-work")
      root.assertTrue(!!work && item.displayProvider(work).mark === "claude",
        "displayProvider carries the record's mark")

      // Machines may disagree about which tool an account name runs; pooling
      // them would charge one subscription with the other's tokens. The first
      // mark seen wins, the conflicting snapshot is ignored, and snapshots
      // from before marks travelled still merge.
      var aggregate = item.aggregateSnapshots([
        JSON.parse('{"deviceId":"one","providers":{"work":{"providerName":"Work","providerMark":"claude","totalPrompts":100,"ready":true}}}'),
        JSON.parse('{"deviceId":"two","providers":{"work":{"providerName":"Work","providerMark":"codex","totalPrompts":40,"ready":true}}}'),
        JSON.parse('{"deviceId":"three","providers":{"legacy":{"providerName":"Old","totalPrompts":7,"ready":true}}}')
      ])
      root.assertTrue(aggregate.providers["work"].totalPrompts === 100,
        "a snapshot whose mark names the other tool is not summed into the account")
      root.assertTrue(aggregate.providers["work"].providerMark === "claude",
        "the aggregate carries the account's mark")
      root.assertTrue(aggregate.providers["legacy"].totalPrompts === 7,
        "a snapshot written before marks travelled still merges")

      // The lookup matches on the mark too, so a local account never reads an
      // aggregate that belongs to the other tool. Sync is switched on for the
      // assertions and off again before its debounce can run anything.
      item.settings = ({ syncMode: "On", syncDir: "/tmp/agents-accounts-fixture-sync" })
      item.aggregateData = aggregate
      root.assertTrue(item.syncedStatsFor("work", "codex") === null,
        "an account does not read an aggregate marked as the other tool")
      root.assertTrue(!!item.syncedStatsFor("work", "claude") && item.syncedStatsFor("work", "claude").totalPrompts === 100,
        "an account reads the aggregate marked as its own tool")
      root.assertTrue(!!item.syncedStatsFor("legacy", "claude") && item.syncedStatsFor("legacy", "claude").totalPrompts === 7,
        "an unmarked legacy aggregate still matches")
      item.settings = ({})

      // The local snapshot records each account's mark for the machines that
      // will read it.
      var snapshot = item.localSnapshot()
      root.assertTrue(String(snapshot.providers["claude"].providerMark) === "claude"
        && String(snapshot.providers["claude-work"].providerMark) === "claude",
        "the local snapshot records each account's mark")

      root.writeResult()
    }
  }
}
