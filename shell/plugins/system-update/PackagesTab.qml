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

  readonly property var packageStatus: updateService ? updateService.packageState : Model.emptyPackageState()
  readonly property var packages: packageStatus && Array.isArray(packageStatus.packages) ? packageStatus.packages : []
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.4)

  function summaryText() {
    if (!updateService) return "Update service is loading"
    if (updateService.packageRefreshing) return "Checking official repositories…"
    if (updateService.packageError !== "") return updateService.packageError
    if (packageStatus.state === "loading") return "Repository packages have not been checked"
    if (packageStatus.state === "unavailable") return "Repository scan unavailable"
    if (packageStatus.state === "invalid") return "Repository scan returned invalid data"
    if (packages.length === 0) return "Official repository packages are up to date"
    return packages.length + " official package" + (packages.length === 1 ? "" : "s") + " ready for review"
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
          color: root.packageStatus.state === "unavailable" || root.packageStatus.state === "invalid" || root.updateService.packageError !== ""
            ? root.bar.urgent
            : root.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          font.bold: root.packages.length > 0
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: Model.checkedLabel(root.packageStatus.checkedEpoch)
          color: root.dim
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Button {
        text: root.updateService.packageRefreshing ? "Checking…" : "Check"
        iconText: "\uf021"
        enabled: !root.updateService.packageRefreshing
        foreground: root.foreground
        fontFamily: root.bar.fontFamily
        fontSize: Style.font.bodySmall
        bordered: true
        onClicked: root.updateService.refreshPackages()
      }
    }

    PanelSeparator {
      Layout.fillWidth: true
      foreground: root.foreground
    }

    GridLayout {
      Layout.fillWidth: true
      columns: 3
      columnSpacing: Style.space(12)
      visible: root.packages.length > 0

      PanelSectionHeader {
        Layout.fillWidth: true
        text: "PACKAGE"
        foreground: root.foreground
        fontFamily: root.bar.fontFamily
      }
      PanelSectionHeader {
        Layout.preferredWidth: Style.space(138)
        text: "INSTALLED"
        foreground: root.foreground
        fontFamily: root.bar.fontFamily
      }
      PanelSectionHeader {
        Layout.preferredWidth: Style.space(138)
        text: "TARGET"
        foreground: root.foreground
        fontFamily: root.bar.fontFamily
      }
    }

    ListView {
      id: packageList
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      spacing: 0
      model: root.packages
      visible: root.packages.length > 0
      boundsBehavior: Flickable.StopAtBounds

      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      delegate: Item {
        required property var modelData
        width: ListView.view.width
        height: Math.max(Style.space(38), packageRow.implicitHeight + Style.space(12))

        RowLayout {
          id: packageRow
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(12)

          Text {
            Layout.fillWidth: true
            text: modelData.name
            color: root.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
          Text {
            Layout.preferredWidth: Style.space(138)
            text: modelData.installed
            color: root.dim
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }
          Text {
            Layout.preferredWidth: Style.space(138)
            text: modelData.target
            color: Color.accent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            elide: Text.ElideRight
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
      visible: root.packages.length === 0

      Column {
        anchors.centerIn: parent
        spacing: Style.space(8)

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.updateService.packageRefreshing ? "\uf021" : (root.packageStatus.state === "current" ? "\uf058" : "\uf071")
          color: root.packageStatus.state === "current" ? Color.accent : root.dim
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

    PanelSeparator {
      Layout.fillWidth: true
      foreground: root.foreground
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)

      Text {
        Layout.fillWidth: true
        text: "Applies through the full Omarchy update flow"
        color: root.dim
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Button {
        text: root.packages.length > 0 ? "Review & update" : "Run update"
        iconText: "\uf019"
        enabled: !root.updateService.packageRefreshing
        foreground: root.foreground
        accent: Color.accent
        fontFamily: root.bar.fontFamily
        fontSize: Style.font.bodySmall
        bordered: true
        onClicked: root.updateService.launchPackageUpdate()
      }
    }
  }
}
