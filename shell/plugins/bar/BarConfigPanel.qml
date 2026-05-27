import QtQuick
import qs.Commons
import qs.Ui

Panel {
  id: root

  moduleName: "omarchy.bar-config"
  manageIpc: false

  property Item anchorItem: null
  property string focusSection: "transparency"
  property int positionIndex: 0
  property bool cursorActive: false
  property int phraseIndex: 0

  readonly property string currentPosition: bar ? bar.position : "top"
  readonly property bool transparent: bar ? bar.requestedTransparent === true : false
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var heroPhrases: [
    "Picking Sides",
    "Choose Transparency",
    "Edge Decisions",
    "Bar Exam",
    "Top Shelf Thinking",
    "Side Quest Settings"
  ]
  readonly property string heroPhraseText: heroPhrases[phraseIndex % heroPhrases.length]
  readonly property var positionOptions: [
    { value: "top", label: "Top" },
    { value: "bottom", label: "Bottom" },
    { value: "left", label: "Left" },
    { value: "right", label: "Right" }
  ]

  function normalizePosition(value) {
    var next = String(value || "")
    return /^(top|bottom|left|right)$/.test(next) ? next : "top"
  }

  function positionLabel(value) {
    var next = normalizePosition(value)
    return next.charAt(0).toUpperCase() + next.slice(1)
  }

  function currentPositionIndex() {
    var current = normalizePosition(currentPosition)
    for (var i = 0; i < positionOptions.length; i++)
      if (positionOptions[i].value === current) return i
    return 0
  }

  function mutateBarConfig(mutator) {
    if (!bar || !bar.shell || typeof bar.shell.mutateShellConfig !== "function") return false
    bar.shell.mutateShellConfig(function(config) {
      if (!Util.isPlainObject(config.bar)) config.bar = {}
      mutator(config.bar)
    })
    return true
  }

  function setTransparency(value) {
    var next = value === true
    if (mutateBarConfig(function(barConfig) { barConfig.transparent = next })) return
    if (bar && typeof bar.setRequestedTransparency === "function") bar.setRequestedTransparency(next)
  }

  function setPosition(value) {
    var next = normalizePosition(value)
    if (mutateBarConfig(function(barConfig) { barConfig.position = next })) return
    if (bar) bar.position = next
  }

  function moveCursor(dx, dy) {
    if (!cursorActive) {
      cursorActive = true
      return
    }

    if (dy !== 0) {
      focusSection = focusSection === "transparency" ? "position" : "transparency"
      if (focusSection === "position") positionIndex = currentPositionIndex()
      return
    }

    if (dx !== 0 && focusSection === "position") {
      var count = positionOptions.length
      positionIndex = (positionIndex + (dx > 0 ? 1 : -1) + count) % count
    }
  }

  function activateCursor() {
    if (focusSection === "transparency") {
      setTransparency(!transparent)
      return
    }

    var option = positionOptions[positionIndex]
    if (option) setPosition(option.value)
  }

  onOpenedChanged: {
    if (!opened) return
    focusSection = "transparency"
    positionIndex = currentPositionIndex()
    cursorActive = false
  }

  onCurrentPositionChanged: if (!cursorActive || focusSection === "position") positionIndex = currentPositionIndex()

  Timer {
    id: phraseTimer
    interval: 2200
    running: root.opened
    repeat: true
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: root.phraseIndex = (root.phraseIndex + 1) % root.heroPhrases.length
    }
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  Component {
    id: heroIconComponent

    Text {
      text: ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.display
    }
  }

  KeyboardPanel {
    id: panel

    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher

      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()

      Column {
        id: contentColumn

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        PanelHero {
          id: hero

          width: parent.width
          iconComponent: heroIconComponent
          title: "Bar"
          meta: root.heroPhraseText
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Column {
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "APPEARANCE"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Toggle {
            width: parent.width
            label: "Transparency"
            description: root.transparent ? "Wallpaper visible" : "Solid background"
            checked: root.transparent
            hasCursor: root.cursorActive && root.focusSection === "transparency"
            foreground: root.foreground
            accent: Color.accent
            fontFamily: root.fontFamily
            onClicked: root.setTransparency(!root.transparent)
            onHovered: function(h) {
              if (!h) return
              root.cursorActive = true
              root.focusSection = "transparency"
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "POSITION"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          ButtonGroup {
            id: positionGroup

            width: parent.width
            options: root.positionOptions
            value: root.currentPosition
            foreground: root.foreground
            background: "transparent"
            accent: Color.accent
            fontFamily: root.fontFamily
            focusable: false
            cursorIndex: root.cursorActive && root.focusSection === "position" ? root.positionIndex : -1
            onChanged: function(value) { root.setPosition(value) }
            onHovered: function(index, hovered) {
              if (!hovered) return
              root.cursorActive = true
              root.focusSection = "position"
              root.positionIndex = index
            }
          }
        }
      }
    }
  }
}
