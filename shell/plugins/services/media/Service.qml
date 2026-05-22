import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire

Item {
  id: root

  property var shell: null
  property string preferredPlayerKey: ""
  property var playerStartedAt: ({})
  property int playSerial: 0

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var playbackStreams: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.isStream && isPlaybackStream(n) && n.audio) list.push(n)
    }
    return list
  }
  readonly property var sourcePlayers: orderedSourcePlayers()
  readonly property var sourceCyclePlayers: orderedCycleSourcePlayers()
  readonly property var activePlayer: selectActivePlayer()
  readonly property bool hasMedia: activePlayer !== null && (activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property string title: activePlayer ? (activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? (activePlayer.trackArtist || "") : ""
  readonly property string album: activePlayer && activePlayer.trackAlbum ? activePlayer.trackAlbum : ""
  readonly property string artUrl: activePlayer && activePlayer.trackArtUrl ? activePlayer.trackArtUrl : ""
  readonly property string identity: activePlayer ? (activePlayer.identity || activePlayer.desktopEntry || "") : ""

  function isProxyPlayer(player) {
    var dbusName = String(player && player.dbusName || "").toLowerCase()
    var desktopEntry = String(player && player.desktopEntry || "").toLowerCase()
    return dbusName.indexOf("playerctld") !== -1 || desktopEntry === "playerctld"
  }

  function hasMetadata(player) {
    return !!(player && (player.trackTitle || player.trackArtist || player.identity || player.desktopEntry))
  }

  function hasTrackMetadata(player) {
    return !!(player && (player.trackTitle || player.trackArtist || player.trackAlbum || player.trackArtUrl))
  }

  function playerCanControl(player) {
    return !!(player && (player.canTogglePlaying || player.canPlay || player.canPause || player.canGoNext || player.canGoPrevious))
  }

  function canHandleAction(player, action) {
    if (!player) return false
    if (action === "next") return !!player.canGoNext
    if (action === "previous") return !!player.canGoPrevious
    if (action === "play") return !!(player.canPlay || player.canTogglePlaying)
    if (action === "pause") return !!(player.canPause || player.canTogglePlaying)
    if (action === "playPause") return !!(player.canTogglePlaying || player.canPlay || player.canPause)
    return false
  }

  function canCycleSource(player) {
    return !!(player && hasMetadata(player) && (player.isPlaying || player.canPlay))
  }

  function nodeProps(node) {
    return node && node.ready && node.properties ? node.properties : {}
  }

  function isPlaybackStream(node) {
    if (!node || !node.isStream) return false
    if (node.isSink === true) return true

    var mediaClass = String(node.type || "")
    return mediaClass.indexOf("Stream/Output/Audio") !== -1
      || mediaClass.indexOf("AudioOutStream") !== -1
      || mediaClass.indexOf("Output") !== -1
  }

  function streamLabelKey(label) {
    var key = String(label || "").toLowerCase()
    key = key.replace(/^pipewire alsa \[/, "")
    key = key.replace(/\]$/, "")
    key = key.replace(/^alsa playback \[/, "")
    key = key.replace(/[^a-z0-9]+/g, "")
    return key
  }

  function rawStreamLabel(node) {
    if (!node) return ""
    var p = nodeProps(node)
    return p["application.name"]
      || node.description
      || p["media.name"]
      || p["node.name"]
      || node.name
  }

  function playerAppLabel(player) {
    if (!player) return ""
    var dbus = String(player.dbusName || "")
    dbus = dbus.replace(/^org\.mpris\.MediaPlayer2\./, "")
    dbus = dbus.replace(/\.instance[0-9]+$/, "")
    return player.desktopEntry || player.identity || dbus
  }

  function playerHasPlaybackStream(player) {
    var playerKey = streamLabelKey(playerAppLabel(player))
    if (!playerKey) return false

    for (var i = 0; i < playbackStreams.length; i++) {
      var streamKey = streamLabelKey(rawStreamLabel(playbackStreams[i]))
      if (!streamKey) continue
      if (streamKey === playerKey
          || streamKey.indexOf(playerKey) !== -1
          || playerKey.indexOf(streamKey) !== -1)
        return true
    }

    return false
  }

  function playerKey(player) {
    if (!player) return ""
    return String(player.dbusName || player.desktopEntry || player.identity || "")
  }

  function playerForKey(key) {
    if (!key) return null
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (playerKey(p) === key) return p
    }
    return null
  }

  function playerOrder(player, fallback) {
    var key = playerKey(player)
    var value = key ? playerStartedAt[key] : undefined
    return value === undefined ? fallback : value
  }

  function syncPlayingOrder() {
    var next = {}
    var alive = {}
    var serial = playSerial

    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      var key = playerKey(p)
      if (!key) continue

      alive[key] = true
      if (!p.isPlaying) continue

      if (playerStartedAt[key] === undefined) {
        serial += 1
        next[key] = serial
      } else {
        next[key] = playerStartedAt[key]
      }
    }

    if (preferredPlayerKey && !alive[preferredPlayerKey]) preferredPlayerKey = ""

    playSerial = serial
    playerStartedAt = next
  }

  function orderedSourcePlayers() {
    var list = []
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (hasMetadata(p)) list.push(p)
    }

    list.sort(function(a, b) {
      if (!!a.isPlaying !== !!b.isPlaying) return a.isPlaying ? -1 : 1
      if (isProxyPlayer(a) !== isProxyPlayer(b)) return isProxyPlayer(a) ? 1 : -1
      if (a.isPlaying && b.isPlaying) {
        var orderDelta = playerOrder(a, 1000) - playerOrder(b, 1000)
        if (orderDelta !== 0) return orderDelta
      }
      return labelFor(a).localeCompare(labelFor(b))
    })

    return list
  }

  function orderedCycleSourcePlayers() {
    var list = []
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (canCycleSource(p)) list.push(p)
    }

    list.sort(function(a, b) {
      if (isProxyPlayer(a) !== isProxyPlayer(b)) return isProxyPlayer(a) ? 1 : -1
      return labelFor(a).localeCompare(labelFor(b))
    })

    return list
  }

  function oldestPlayingPlayer(requirePlaybackStream) {
    var oldest = null
    var oldestOrder = 0
    var playingProxy = null
    var proxyOrder = 0

    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p) continue

      var proxyPlayer = isProxyPlayer(p)
      if (p.isPlaying) {
        if (requirePlaybackStream && !playerHasPlaybackStream(p)) continue

        var order = playerOrder(p, i + 1000)
        if (!proxyPlayer && (!oldest || order < oldestOrder)) {
          oldest = p
          oldestOrder = order
        } else if (proxyPlayer && (!playingProxy || order < proxyOrder)) {
          playingProxy = p
          proxyOrder = order
        }
      }
    }

    return oldest || playingProxy || null
  }

  function selectActivePlayer() {
    var preferred = null
    var trackPlayer = null
    var trackProxy = null
    var streamPlayer = null
    var streamProxy = null
    var controllablePlayer = null
    var controllableProxy = null
    var identityPlayer = null
    var identityProxy = null

    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p) continue

      var proxy = isProxyPlayer(p)

      if (preferredPlayerKey && playerKey(p) === preferredPlayerKey && hasMetadata(p)) preferred = p

      if (playerHasPlaybackStream(p)) {
        if (!proxy && !streamPlayer) streamPlayer = p
        else if (proxy && !streamProxy) streamProxy = p
      } else if (hasTrackMetadata(p)) {
        if (!proxy && !trackPlayer) trackPlayer = p
        else if (proxy && !trackProxy) trackProxy = p
      } else if (playerCanControl(p)) {
        if (!proxy && !controllablePlayer) controllablePlayer = p
        else if (proxy && !controllableProxy) controllableProxy = p
      } else if (hasMetadata(p)) {
        if (!proxy && !identityPlayer) identityPlayer = p
        else if (proxy && !identityProxy) identityProxy = p
      }
    }

    if (preferred && preferred.isPlaying) return preferred
    var streamCandidate = streamPlayer || streamProxy
    var streamPreferred = preferred && playerHasPlaybackStream(preferred) ? preferred : null
    return oldestPlayingPlayer(true) || oldestPlayingPlayer(false) || streamPreferred || streamCandidate || preferred || trackPlayer || trackProxy || controllablePlayer || controllableProxy || identityPlayer || identityProxy || null
  }

  function labelFor(player) {
    if (!player) return ""
    return player.trackTitle || player.identity || player.desktopEntry || ""
  }

  function osdMessage(player, fallback) {
    if (!player) return fallback
    var label = labelFor(player)
    if (label && player.trackArtist) return label + " - " + player.trackArtist
    return label || fallback
  }

  function showOsd(actionLabel, iconName, player) {
    if (!shell) return
    shell.summon("omarchy.osd", JSON.stringify({
      icon: iconName || "media",
      message: osdMessage(player || activePlayer, actionLabel)
    }))
  }

  function selectPlayer(key) {
    var player = playerForKey(key)
    if (!player || !hasMetadata(player)) return false
    preferredPlayerKey = playerKey(player)
    return true
  }

  function playPlayer(player) {
    if (!player) return false
    if (player.canPlay) {
      player.play()
      return true
    }
    return false
  }

  function pausePlayer(player) {
    if (!player) return false
    if (player.canPause) {
      player.pause()
      return true
    }
    if (player.canTogglePlaying && player.isPlaying) {
      player.togglePlaying()
      return true
    }
    return false
  }

  function switchSource(delta, transferPlayback, showFeedback) {
    var list = sourceCyclePlayers
    if (!list || list.length === 0) return false

    var activeKey = playerKey(activePlayer)
    var index = 0
    for (var i = 0; i < list.length; i++) {
      if (playerKey(list[i]) === activeKey) {
        index = i
        break
      }
    }

    index = (index + delta + list.length) % list.length
    var current = activePlayer
    var next = list[index]
    var currentWasPlaying = current && current.isPlaying
    var currentKey = playerKey(current)
    var nextKey = playerKey(next)

    preferredPlayerKey = nextKey

    if (transferPlayback && currentWasPlaying && next && nextKey !== currentKey) {
      var nextWasPlaying = next.isPlaying
      var nextStarted = nextWasPlaying || playPlayer(next)
      if (nextStarted) pausePlayer(current)
    }

    if (showFeedback !== false) Qt.callLater(function() {
      root.showOsd("Source", "media-source", next)
    })

    return true
  }

  function playerForAction(action, targetKey) {
    var targeted = playerForKey(targetKey)
    if (targeted) return targeted

    if (action === "pause" || action === "playPause") {
      var oldest = oldestPlayingPlayer(true) || oldestPlayingPlayer(false)
      if (oldest) return oldest
    }

    if (canHandleAction(activePlayer, action)) return activePlayer

    var list = sourcePlayers
    for (var i = 0; i < list.length; i++) {
      if (canHandleAction(list[i], action)) return list[i]
    }

    return activePlayer
  }

  function runAction(action, showFeedback, targetKey) {
    var player = playerForAction(action, targetKey)
    var key = playerKey(player)
    var actionLabel = "Play/pause"
    var iconName = "media"
    var handled = false

    if (action === "next") {
      actionLabel = "Next"
      iconName = "media-next"
      if (player && player.canGoNext) {
        player.next()
        handled = true
      }
    } else if (action === "previous") {
      actionLabel = "Previous"
      iconName = "media-previous"
      if (player && player.canGoPrevious) {
        player.previous()
        handled = true
      }
    } else if (action === "play") {
      actionLabel = "Play"
      iconName = "media-play"
      if (player && player.canPlay) {
        player.play()
        handled = true
      } else if (player && player.canTogglePlaying && !player.isPlaying) {
        player.togglePlaying()
        handled = true
      }
    } else if (action === "pause") {
      actionLabel = "Pause"
      iconName = "media-pause"
      if (player && player.canPause) {
        player.pause()
        handled = true
      } else if (player && player.canTogglePlaying && player.isPlaying) {
        player.togglePlaying()
        handled = true
      }
    } else if (action === "playPause") {
      actionLabel = player && player.isPlaying ? "Pause" : "Play"
      iconName = player && player.isPlaying ? "media-pause" : "media-play"
      if (player && player.isPlaying && player.canPause) {
        player.pause()
        handled = true
      } else if (player && !player.isPlaying && player.canPlay) {
        player.play()
        handled = true
      } else if (player && player.canTogglePlaying) {
        player.togglePlaying()
        handled = true
      }
    }

    if (handled && key) preferredPlayerKey = key
    if (showFeedback !== false) Qt.callLater(function() { root.showOsd(actionLabel, iconName, player) })
    return handled
  }

  Timer {
    interval: 500
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.syncPlayingOrder()
  }

  PwObjectTracker { objects: root.playbackStreams }

  function statusJson() {
    var p = activePlayer
    return JSON.stringify({
      hasPlayer: p !== null,
      hasMedia: root.hasMedia,
      playing: p ? !!p.isPlaying : false,
      identity: p ? (p.identity || "") : "",
      desktopEntry: p ? (p.desktopEntry || "") : "",
      title: p ? (p.trackTitle || "") : "",
      artist: p ? (p.trackArtist || "") : "",
      album: p && p.trackAlbum ? p.trackAlbum : "",
      artUrl: p && p.trackArtUrl ? p.trackArtUrl : "",
      canGoNext: p ? !!p.canGoNext : false,
      canGoPrevious: p ? !!p.canGoPrevious : false,
      canTogglePlaying: p ? !!p.canTogglePlaying : false
    })
  }

  IpcHandler {
    target: "media"

    function status(): string {
      return root.statusJson()
    }

    function playPause(): string {
      return root.runAction("playPause", true) ? "ok" : "unhandled"
    }

    function next(): string {
      return root.runAction("next", true) ? "ok" : "unhandled"
    }

    function previous(): string {
      return root.runAction("previous", true) ? "ok" : "unhandled"
    }

    function play(): string {
      return root.runAction("play", true) ? "ok" : "unhandled"
    }

    function pause(): string {
      return root.runAction("pause", true) ? "ok" : "unhandled"
    }

    function sourceNext(): string {
      return root.switchSource(1, false, true) ? "ok" : "unhandled"
    }

    function sourcePrevious(): string {
      return root.switchSource(-1, false, true) ? "ok" : "unhandled"
    }

    function sourceSwitch(): string {
      return root.switchSource(1, true, true) ? "ok" : "unhandled"
    }

    function sourceSwitchPrevious(): string {
      return root.switchSource(-1, true, true) ? "ok" : "unhandled"
    }

    function ping(): string {
      return "ok"
    }
  }
}
