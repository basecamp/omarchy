import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property var service: null
  property var shell: null
  property var manifest: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  property bool opened: false
  property string searchText: ""
  property string selectedKey: ""
  property string cursorKey: ""
  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null
  readonly property bool settingsLoaded: !!root.service && root.service.settingsLoaded === true
  readonly property bool catalogLoaded: !!root.service && root.service.catalogLoaded === true
  readonly property bool settingsWritable: root.settingsLoaded && root.service.settingsWritable !== false

  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color dimForeground: Util.alpha(foreground, 0.58)
  readonly property color scrim: Color.menu.scrim
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
  readonly property int cardPadding: Style.spacing.panelPadding
  readonly property bool compact: panel.width < Style.space(720) || panel.height < Style.space(560)
  readonly property var applications: service && typeof service.applicationsList === "function" ? service.applicationsList() : []
  readonly property var filteredApplications: {
    var query = searchText.trim().toLowerCase()
    if (!query) return applications

    var matches = []
    for (var i = 0; i < applications.length; i++) {
      var application = applications[i]
      var haystack = [application.label, application.app, application.desktopEntry, application.source, application.searchText].join(" ").toLowerCase()
      if (haystack.indexOf(query) >= 0) matches.push(application)
    }
    return matches
  }
  readonly property var selectedApplication: {
    for (var i = 0; i < filteredApplications.length; i++)
      if (String(filteredApplications[i].key) === selectedKey) return filteredApplications[i]
    return null
  }

  function open(payloadJson) {
    if (root.shell && typeof root.shell.serviceFor === "function")
      root.service = root.shell.serviceFor((root.manifest && root.manifest.id) || "omarchy.notifications")
    root.opened = true
    root.searchText = ""
    root.selectedKey = root.applications.length > 0 ? String(root.applications[0].key) : ""
    if (root.appLibrary) root.appLibrary.refreshIcons()
    Qt.callLater(function() {
      if (root.opened) searchField.forceActiveFocus()
    })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "omarchy.notifications")
    else
      root.close()
  }

  function ensureSelection() {
    if (root.filteredApplications.length === 0) {
      root.selectedKey = ""
      return
    }
    if (!root.selectedApplication)
      root.selectedKey = String(root.filteredApplications[0].key)
  }

  function setMode(mode) {
    if (!root.settingsWritable || !root.selectedApplication || typeof root.service.setApplicationMode !== "function") return
    root.service.setApplicationMode(root.selectedApplication.key, mode)
  }

  function toggleDoNotDisturb() {
    if (!root.settingsWritable || typeof root.service.setDoNotDisturb !== "function") return
    root.service.setDoNotDisturb(!root.service.doNotDisturb)
  }

  function iconPath(application) {
    if (!application) return ""
    var icon = String(application.appIcon || application.desktopEntry || "")
    if (root.appLibrary) return root.appLibrary.iconSource(icon)
    return icon ? Quickshell.iconPath(icon, true) : ""
  }

  function applicationSubtitle(application) {
    if (!application || !application.source) return ""
    var shared = Number(application.memberCount || 0) > 1 ? " (shared origin)" : ""
    return String(application.source) + shared
  }

  onApplicationsChanged: ensureSelection()
  onFilteredApplicationsChanged: ensureSelection()

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-notification-controls"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle {
      anchors.fill: parent
      color: root.scrim

      MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
      }
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.AfterItem
      Keys.onEscapePressed: root.dismiss()

      BorderSurface {
        id: card
        anchors.centerIn: parent
        width: Math.min(Style.space(900), panel.width - Style.gapsOut * 4)
        height: Math.min(Style.space(640), panel.height - Style.gapsOut * 4)
        radius: Style.cornerRadius
        color: root.background
        borderSpec: root.borderSpec
        padding: root.cardPadding

        MouseArea { anchors.fill: parent; onClicked: {} }

        ColumnLayout {
          anchors.fill: parent
          anchors.topMargin: card.contentTopInset
          anchors.rightMargin: card.contentRightInset
          anchors.bottomMargin: card.contentBottomInset
          anchors.leftMargin: card.contentLeftInset
          spacing: Style.spacing.lg

          Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(titleColumn.implicitHeight, dndControl.implicitHeight)

            Column {
              id: titleColumn
              anchors.left: parent.left
              anchors.right: dndControl.left
              anchors.rightMargin: Style.spacing.lg
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.xs

              Text {
                width: parent.width
                text: "Notifications"
                color: root.foreground
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.heading
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                text: !root.settingsLoaded
                  ? "Loading notification settings..."
                  : (root.settingsWritable
                    ? "Choose how each application reaches you"
                    : "Settings were created by a newer Omarchy version")
                color: root.dimForeground
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }

            Item {
              id: dndControl
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              implicitWidth: dndRow.implicitWidth
              implicitHeight: dndSwitch.implicitHeight
              activeFocusOnTab: root.settingsWritable
              enabled: root.settingsWritable

              Keys.onReturnPressed: root.toggleDoNotDisturb()
              Keys.onEnterPressed: root.toggleDoNotDisturb()
              Keys.onSpacePressed: root.toggleDoNotDisturb()
              Accessible.role: Accessible.CheckBox
              Accessible.name: "Do not disturb"
              Accessible.checkable: true
              Accessible.checked: root.service ? root.service.doNotDisturb : false
              Accessible.onPressAction: root.toggleDoNotDisturb()
              Accessible.onToggleAction: root.toggleDoNotDisturb()

              Row {
                id: dndRow
                anchors.centerIn: parent
                spacing: Style.spacing.controlGap

                Text {
                  text: "Do not disturb"
                  color: dndControl.enabled ? root.foreground : root.dimForeground
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.body
                  anchors.verticalCenter: parent.verticalCenter
                }

                ToggleSwitch {
                  id: dndSwitch
                  checked: root.service ? root.service.doNotDisturb : false
                  enabled: root.settingsWritable
                  foreground: root.foreground
                  hasCursor: dndControl.activeFocus
                  anchors.verticalCenter: parent.verticalCenter
                  onToggled: root.toggleDoNotDisturb()
                }
              }
            }
          }

          PanelSeparator {
            Layout.fillWidth: true
            foreground: root.foreground
          }

          GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: root.compact ? 1 : 3
            rowSpacing: Style.spacing.lg
            columnSpacing: Style.spacing.lg

            ColumnLayout {
              Layout.fillWidth: true
              Layout.fillHeight: true
              Layout.preferredWidth: root.compact ? card.width : Style.space(300)
              Layout.maximumHeight: root.compact ? Style.space(210) : panel.height
              spacing: Style.spacing.md

              TextField {
                id: searchField
                Layout.fillWidth: true
                text: root.searchText
                placeholderText: "Search applications"
                foreground: root.foreground
                onTextChanged: root.searchText = text
              }

              ListView {
                id: applicationList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Style.spacing.xs
                boundsBehavior: Flickable.StopAtBounds
                model: root.filteredApplications
                currentIndex: {
                  for (var i = 0; i < root.filteredApplications.length; i++)
                    if (String(root.filteredApplications[i].key) === root.selectedKey) return i
                  return -1
                }
                onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: CursorSurface {
                  id: applicationRow
                  required property var modelData
                  required property int index
                  readonly property bool chosen: String(modelData.key) === root.selectedKey
                  readonly property string subtitle: root.applicationSubtitle(modelData)

                  width: ListView.view.width
                  implicitHeight: Math.max(Style.space(52), rowContent.implicitHeight + Style.spacing.md)
                  activeFocusOnTab: true
                  current: chosen
                  hasCursor: String(modelData.key) === root.cursorKey
                  foreground: root.foreground
                  fill: Style.hoverFillFor(root.foreground, Color.accent)
                  currentFill: Style.selectedFillFor(root.foreground, Color.accent)

                  function selectApplication() {
                    root.selectedKey = String(modelData.key)
                    root.cursorKey = root.selectedKey
                  }

                  Keys.onReturnPressed: selectApplication()
                  Keys.onEnterPressed: selectApplication()
                  Keys.onSpacePressed: selectApplication()
                  onActiveFocusChanged: if (activeFocus) root.cursorKey = String(modelData.key)
                  Accessible.role: Accessible.ListItem
                  Accessible.name: modelData.label || modelData.app || "Unknown application"
                  Accessible.description: subtitle
                  Accessible.focusable: true
                  Accessible.selectable: true
                  Accessible.selected: chosen
                  Accessible.onPressAction: selectApplication()

                  RowLayout {
                    id: rowContent
                    anchors.fill: parent
                    anchors.margins: Style.spacing.sm
                    spacing: Style.spacing.sm

                    Item {
                      Layout.preferredWidth: Style.space(28)
                      Layout.preferredHeight: Style.space(28)

                      Text {
                        anchors.centerIn: parent
                        text: String(applicationRow.modelData.label || applicationRow.modelData.app || "?").charAt(0).toUpperCase()
                        color: root.dimForeground
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.title
                        font.bold: true
                      }

                      Image {
                        anchors.fill: parent
                        source: root.iconPath(applicationRow.modelData)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        visible: status === Image.Ready
                      }
                    }

                    ColumnLayout {
                      Layout.fillWidth: true
                      spacing: Style.spacing.xs

                      Text {
                        Layout.fillWidth: true
                        text: applicationRow.modelData.label || applicationRow.modelData.app || "Unknown application"
                        color: root.foreground
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.body
                        font.bold: applicationRow.chosen
                        elide: Text.ElideRight
                      }

                      Text {
                        visible: applicationRow.subtitle !== ""
                        Layout.fillWidth: true
                        text: applicationRow.subtitle
                        color: root.dimForeground
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }
                    }
                  }

                  HoverHandler {
                    onHoveredChanged: if (hovered) root.cursorKey = String(applicationRow.modelData.key)
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      applicationRow.selectApplication()
                      applicationRow.forceActiveFocus()
                    }
                  }
                }

                Text {
                  anchors.centerIn: parent
                  width: Math.max(0, parent.width - Style.spacing.xl * 2)
                  visible: root.filteredApplications.length === 0
                  text: !root.catalogLoaded
                    ? "Loading applications..."
                    : (root.applications.length === 0
                      ? "No applications available."
                      : "No applications match your search."
                    )
                  color: root.dimForeground
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.bodySmall
                  horizontalAlignment: Text.AlignHCenter
                  wrapMode: Text.WordWrap
                }
              }
            }

            Rectangle {
              visible: !root.compact
              Layout.fillHeight: true
              Layout.preferredWidth: Math.max(1, Style.normalBorderWidth)
              color: Util.alpha(root.foreground, 0.18)
            }

            ColumnLayout {
              Layout.fillWidth: true
              Layout.fillHeight: true
              Layout.preferredWidth: Style.space(500)
              spacing: Style.spacing.md

              ColumnLayout {
                visible: !!root.selectedApplication
                Layout.fillWidth: true
                spacing: Style.spacing.xs

                Text {
                  Layout.fillWidth: true
                  text: root.selectedApplication ? root.selectedApplication.label : ""
                  color: root.foreground
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  visible: root.applicationSubtitle(root.selectedApplication) !== ""
                  Layout.fillWidth: true
                  text: root.applicationSubtitle(root.selectedApplication)
                  color: root.dimForeground
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
              }

              Text {
                visible: !!root.selectedApplication
                text: "DELIVERY"
                color: root.dimForeground
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
              }

              Repeater {
                model: [
                  { value: "normal", label: "Normal", description: "Show popups and keep notifications in history." },
                  { value: "history", label: "History only", description: "Skip popups but keep notifications in history." },
                  { value: "off", label: "Off", description: "Discard new notifications from this application." }
                ]

                ColumnLayout {
                  required property var modelData
                  Layout.fillWidth: true
                  visible: !!root.selectedApplication
                  spacing: Style.spacing.xs

                  Button {
                    Layout.fillWidth: true
                    text: modelData.label
                    leftAlign: true
                    focusable: true
                    bordered: true
                    enabled: root.settingsWritable
                    selected: !!root.selectedApplication && root.selectedApplication.mode === modelData.value
                    foreground: root.foreground
                    fontFamily: Style.font.menuFamily
                    onClicked: root.setMode(modelData.value)
                  }

                  Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: Style.spacing.controlPaddingX
                    Layout.rightMargin: Style.spacing.controlPaddingX
                    text: modelData.description
                    color: root.dimForeground
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }
                }
              }

              Item { Layout.fillHeight: true }

              Text {
                visible: !root.selectedApplication
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: root.applications.length === 0
                  ? "No applications available."
                  : "Select an application to change its delivery mode."
                color: root.dimForeground
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap
              }
            }
          }
        }
      }
    }
  }
}
