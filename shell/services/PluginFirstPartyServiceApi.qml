import QtQuick

// Narrow proxy for the non-authentication first-party services used by the
// built-in bar. It intentionally has no generic property or method forwarding.
QtObject {
  required property string ownerPluginId
  required property string serviceId

  property bool stayAwake: false
  property bool enabled: false
  property bool doNotDisturb: false
  property var activePlayer: null
  property var sourcePlayers: []

  property var _setIdleEnabled: null
  property var _setNightlight: null
  property var _setDoNotDisturb: null
  property var _runAction: null
  property var _playerKey: null
  property var _selectPlayer: null

  function setIdleEnabled(value) {
    if (serviceId === "omarchy.idle" && _setIdleEnabled) _setIdleEnabled(!!value)
  }

  function setNightlight(value) {
    if (serviceId === "omarchy.nightlight" && _setNightlight) _setNightlight(!!value)
  }

  function setDoNotDisturb(value) {
    if (serviceId === "omarchy.notifications" && _setDoNotDisturb) _setDoNotDisturb(!!value)
  }

  function runAction(action, showFeedback, playerId) {
    if (serviceId === "omarchy.media" && _runAction)
      _runAction(String(action || ""), !!showFeedback, String(playerId || ""))
  }

  function playerKey(player) {
    return serviceId === "omarchy.media" && _playerKey ? _playerKey(player) : ""
  }

  function selectPlayer(playerId) {
    if (serviceId === "omarchy.media" && _selectPlayer) _selectPlayer(String(playerId || ""))
  }
}
