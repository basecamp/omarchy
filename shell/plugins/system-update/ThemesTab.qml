import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  required property var updateService
  required property var bar

  property string confirmRemoveName: ""

  readonly property var themeStatus: updateService ? updateService.themeState : Model.emptyThemeState()
  readonly property var themes: themeStatus && Array.isArray(themeStatus.themes) ? themeStatus.themes : []
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.4)

  function summaryText() {
    if (!updateService) return "Update service is loading"
    if (updateService.themeRefreshing) return "Checking user Git themes…"
    if (updateService.themeError !== "") return updateService.themeError
    if (Number(themeStatus.checkedEpoch || 0) <= 0) return "User themes have not been checked"
    if (themeStatus.total === 0) return "No user Git themes installed"
    if (themeStatus.outdated === 0 && themeStatus.review === 0)
      return themeStatus.total + " user theme" + (themeStatus.total === 1 ? " is" : "s are") + " up to date"
    var parts = []
    if (themeStatus.outdated > 0) parts.push(themeStatus.outdated + " outdated")
    if (themeStatus.blocked > 0) parts.push(themeStatus.blocked + " blocked")
    var otherReview = Math.max(0, Number(themeStatus.review || 0) - Number(themeStatus.blocked || 0))
    if (otherReview > 0) parts.push(otherReview + (otherReview === 1 ? " needs review" : " need review"))
    return parts.join(" · ")
  }

  function stateColor(theme) {
    if (!theme) return root.dim
    if (theme.state === "update") return Color.accent
    if (theme.state === "clean") return root.foreground
    if (theme.state === "unreachable" || theme.state === "invalid") return root.bar.urgent
    return Qt.darker(Color.accent, 1.25)
  }

  onThemesChanged: {
    if (confirmRemoveName === "") return
    for (var i = 0; i < themes.length; i++) {
      if (themes[i].name === confirmRemoveName) return
    }
    confirmRemoveName = ""
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(10)

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(2)

        Text {
          Layout.fillWidth: true
          text: root.summaryText()
          color: root.updateService.themeError !== "" ? root.bar.urgent : root.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          font.bold: root.themeStatus.outdated > 0
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: Model.checkedLabel(root.themeStatus.checkedEpoch) + (root.themeStatus.degraded ? " · incomplete" : "")
          color: root.themeStatus.degraded ? root.bar.urgent : root.dim
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Button {
        text: root.updateService.themeRefreshing ? "Checking…" : "Check"
        iconText: "\uf021"
        enabled: !root.updateService.themeRefreshing && root.updateService.actionKind === ""
        foreground: root.foreground
        fontFamily: root.bar.fontFamily
        fontSize: Style.font.bodySmall
        bordered: true
        onClicked: root.updateService.refreshThemes()
      }
    }

    BorderSurface {
      Layout.fillWidth: true
      Layout.preferredHeight: actionMessage.implicitHeight + Style.space(12)
      visible: root.updateService.actionStatus !== "" || root.updateService.actionError !== ""
      color: Style.normalFillFor(root.foreground, Color.accent)
      borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
      radius: Style.cornerRadius

      Text {
        id: actionMessage
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(8)
        anchors.rightMargin: Style.space(8)
        text: root.updateService.actionError !== "" ? root.updateService.actionError : root.updateService.actionStatus
        color: root.updateService.actionError !== "" ? root.bar.urgent : root.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
    }

    PanelSeparator {
      Layout.fillWidth: true
      foreground: root.foreground
    }

    GridLayout {
      Layout.fillWidth: true
      columns: 3
      columnSpacing: Style.space(10)
      visible: root.themes.length > 0

      PanelSectionHeader {
        Layout.fillWidth: true
        text: "USER THEME"
        foreground: root.foreground
        fontFamily: root.bar.fontFamily
      }
      PanelSectionHeader {
        Layout.preferredWidth: Style.space(145)
        text: "STATUS"
        foreground: root.foreground
        fontFamily: root.bar.fontFamily
      }
      PanelSectionHeader {
        Layout.preferredWidth: Style.space(116)
        text: "ACTIONS"
        horizontalAlignment: Text.AlignRight
        foreground: root.foreground
        fontFamily: root.bar.fontFamily
      }
    }

    ListView {
      id: themeList
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      spacing: 0
      model: root.themes
      visible: root.themes.length > 0
      boundsBehavior: Flickable.StopAtBounds

      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      delegate: Item {
        id: themeRow
        required property var modelData
        width: ListView.view.width
        height: root.confirmRemoveName === modelData.name ? Style.space(72) : Style.space(42)

        readonly property bool actionBusy: root.updateService.actionName === modelData.name
        readonly property bool canUpdate: modelData.state === "update" && modelData.targetCommit !== ""

        RowLayout {
          id: normalRow
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: Style.space(42)
          spacing: Style.space(10)

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)

            Text {
              Layout.fillWidth: true
              text: modelData.name
              color: root.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              font.bold: modelData.current
              elide: Text.ElideRight
            }

            Text {
              visible: modelData.current
              text: "CURRENT"
              color: Color.accent
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          Item {
            Layout.preferredWidth: Style.space(145)
            Layout.fillHeight: true

            Row {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(6)
                height: width
                radius: width / 2
                color: root.stateColor(modelData)
              }
              Text {
                text: themeRow.actionBusy
                  ? (root.updateService.actionKind === "remove" ? "Removing…" : "Updating…")
                  : Model.themeStateLabel(modelData)
                color: root.stateColor(modelData)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }

            MouseArea {
              id: statusMouse
              anchors.fill: parent
              hoverEnabled: true
            }

            PanelToolTip {
              visible: statusMouse.containsMouse
              text: Model.themeStateDetail(modelData)
              fontFamily: root.bar.fontFamily
            }
          }

          RowLayout {
            Layout.preferredWidth: Style.space(116)
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            spacing: Style.space(4)

            Item { Layout.fillWidth: true }

            PanelActionButton {
              iconText: "\uf021"
              tooltipText: themeRow.canUpdate ? "Install reviewed commit" : Model.themeStateDetail(modelData)
              foreground: root.foreground
              hoverColor: Color.accent
              fontFamily: root.bar.fontFamily
              enabled: themeRow.canUpdate && root.updateService.actionKind === "" && !root.updateService.themeRefreshing
              onClicked: root.updateService.updateTheme(modelData)
            }

            PanelActionButton {
              iconText: "\uf2ed"
              tooltipText: modelData.current ? "Select another theme before removing this one" : "Remove user theme"
              foreground: root.foreground
              hoverColor: root.bar.urgent
              fontFamily: root.bar.fontFamily
              enabled: !modelData.current && root.updateService.actionKind === "" && !root.updateService.themeRefreshing
              onClicked: root.confirmRemoveName = modelData.name
            }
          }
        }

        RowLayout {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: Style.space(30)
          visible: root.confirmRemoveName === modelData.name
          spacing: Style.space(8)

          Text {
            Layout.fillWidth: true
            text: "Remove " + modelData.name + "?"
            color: root.bar.urgent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Button {
            text: "Cancel"
            foreground: root.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.caption
            bordered: true
            onClicked: root.confirmRemoveName = ""
          }

          Button {
            text: "Remove"
            foreground: root.bar.urgent
            accent: root.bar.urgent
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.caption
            bordered: true
            onClicked: {
              root.confirmRemoveName = ""
              root.updateService.removeTheme(modelData.name)
            }
          }
        }

        PanelSeparator {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          foreground: root.foreground
          strength: 0.08
        }
      }
    }

    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true
      visible: root.themes.length === 0

      Column {
        anchors.centerIn: parent
        spacing: Style.space(8)

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.updateService.themeRefreshing ? "\uf021" : "\uf1fc"
          color: root.updateService.themeError !== "" ? root.bar.urgent : root.dim
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.display
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.summaryText()
          color: root.dim
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
        }
      }
    }

    Text {
      Layout.fillWidth: true
      text: "Stock themes are maintained through package updates"
      color: root.dim
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideRight
    }
  }
}
