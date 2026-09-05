import QtQuick

// Bar surface exposed to an installed third-party widget. Scalar presentation
// state is mirrored by Bar.qml and operations are delegated through scoped
// callbacks. The facade avoids direct host-Bar injection; it cannot isolate a
// visual child from the parent hierarchy of the QML scene that renders it.
QtObject {
  id: api

  required property string pluginId
  required property string moduleName
  property var shell: null

  property color foreground: "transparent"
  property color barForeground: "transparent"
  property color background: "transparent"
  property color urgent: "transparent"
  property string fontFamily: ""
  property string position: "top"
  property bool vertical: false
  property int barSize: 0
  property bool transparent: false
  property bool foregroundAnimationEnabled: true
  property bool centerSectionRevealHeld: false
  property bool _centerHoverRevealSuppressed: false
  readonly property bool centerHoverRevealSuppressed: _centerHoverRevealSuppressed
  property var activePopout: null
  property var clickTargets: []
  property var layoutConfig: ({})
  readonly property var foreignPopoutMarker: ({ foreign: true })

  property var _showTooltip: null
  property var _hideTooltip: null
  property var _registerClickTarget: null
  property var _unregisterClickTarget: null
  property var _requestPopout: null
  property var _releasePopout: null
  property var _switchPanelFrom: null
  property var _targetBelongsToWindow: null
  property var _moduleWidgets: null
  property var _run: null
  property var _setCenterHoverRevealSuppressed: null

  function setCenterHoverRevealSuppressed(value) {
    if (_setCenterHoverRevealSuppressed) _setCenterHoverRevealSuppressed(!!value)
  }

  function showTooltip(target, text) {
    if (_showTooltip) _showTooltip(target, String(text || ""))
  }

  function hideTooltip(target) {
    if (_hideTooltip) _hideTooltip(target)
  }

  function registerClickTarget(target) {
    if (_registerClickTarget) _registerClickTarget(target)
  }

  function unregisterClickTarget(target) {
    if (_unregisterClickTarget) _unregisterClickTarget(target)
  }

  function requestPopout(owner) {
    if (_requestPopout) _requestPopout(owner)
  }

  function releasePopout(owner) {
    if (_releasePopout) _releasePopout(owner)
  }

  function switchPanelFrom(owner, direction) {
    return _switchPanelFrom ? _switchPanelFrom(owner, direction) : false
  }

  function targetBelongsToWindow(target, window) {
    return _targetBelongsToWindow ? _targetBelongsToWindow(target, window) : false
  }

  function moduleWidgets(id) {
    return _moduleWidgets ? _moduleWidgets(String(id || "")) : []
  }

  function run(command) {
    if (_run) _run(String(command || ""))
  }
}
