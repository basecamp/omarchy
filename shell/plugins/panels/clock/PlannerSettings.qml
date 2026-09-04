import QtQuick
import qs.Commons
import qs.Ui

// Planner settings are persisted through Service.qml. The advanced section is
// intentionally collapsed so first-run setup only asks for timezone and
// availability, while every solver setting remains reachable and editable.
Item {
  id: root

  property var service: null
  property var bar: null
  property color foreground: bar ? bar.foreground : Color.foreground
  property string fontFamily: bar ? bar.fontFamily : Style.font.family
  property string errorText: ""
  property bool advanced: false
  property bool availabilityOpen: false
  property int horizonDays: 14
  property int slotMinutes: 15
  property int solveSeconds: 5
  property int priorityLowWeight: 1
  property int priorityNormalWeight: 5
  property int priorityHighWeight: 25
  property bool cognitiveEnabled: false
  property int lowOutsidePenalty: 0
  property int mediumOutsidePenalty: 0
  property int highOutsidePenalty: 0
  property int highStreakLimit: 1
  property int recoveryMinutes: 30
  property int excessHighPenalty: 60

  signal saved()
  signal cancelled()

  function settings() {
    return root.service && root.service.calendarState
      ? root.service.calendarState.settings
      : {}
  }

  function reset() {
    var value = settings()
    timezoneField.text = value.timezone || ""
    lowStartField.text = value.lowWindowStart || "00:00"
    lowEndField.text = value.lowWindowEnd || "00:00"
    mediumStartField.text = value.mediumWindowStart || "00:00"
    mediumEndField.text = value.mediumWindowEnd || "00:00"
    highStartField.text = value.highWindowStart || "00:00"
    highEndField.text = value.highWindowEnd || "00:00"
    horizonDays = Number(value.horizonDays || 14)
    slotMinutes = Number(value.slotMinutes || 15)
    solveSeconds = Number(value.solveSeconds || 5)
    priorityLowWeight = Number(value.priorityLowWeight || 0)
    priorityNormalWeight = Number(value.priorityNormalWeight || 0)
    priorityHighWeight = Number(value.priorityHighWeight || 0)
    cognitiveEnabled = !!value.cognitiveEnabled
    lowOutsidePenalty = Number(value.lowOutsidePenalty || 0)
    mediumOutsidePenalty = Number(value.mediumOutsidePenalty || 0)
    highOutsidePenalty = Number(value.highOutsidePenalty || 0)
    highStreakLimit = Number(value.highStreakLimit || 1)
    recoveryMinutes = Number(value.recoveryMinutes || 0)
    excessHighPenalty = Number(value.excessHighPenalty || 0)
    errorText = ""
  }

  function availabilityCount() {
    var value = settings().availability || {}
    var count = 0
    for (var key in value) if (Array.isArray(value[key])) count += value[key].length
    return count
  }

  function detectedTimezone() {
    try { return Intl.DateTimeFormat().resolvedOptions().timeZone || "" }
    catch (error) { return "" }
  }

  function save() {
    var patch = {
      timezone: timezoneField.text.trim(),
      horizonDays: horizonDays,
      slotMinutes: slotMinutes,
      solveSeconds: solveSeconds,
      priorityLowWeight: priorityLowWeight,
      priorityNormalWeight: priorityNormalWeight,
      priorityHighWeight: priorityHighWeight,
      cognitiveEnabled: cognitiveEnabled,
      lowWindowStart: lowStartField.text.trim(),
      lowWindowEnd: lowEndField.text.trim(),
      lowOutsidePenalty: lowOutsidePenalty,
      mediumWindowStart: mediumStartField.text.trim(),
      mediumWindowEnd: mediumEndField.text.trim(),
      mediumOutsidePenalty: mediumOutsidePenalty,
      highWindowStart: highStartField.text.trim(),
      highWindowEnd: highEndField.text.trim(),
      highOutsidePenalty: highOutsidePenalty,
      highStreakLimit: highStreakLimit,
      recoveryMinutes: recoveryMinutes,
      excessHighPenalty: excessHighPenalty
    }
    var next = root.service ? root.service.updateSettings(patch) : null
    if (next) root.saved()
    else root.errorText = root.service ? root.service.lastSolverError : "Settings could not be saved."
  }

  Component.onCompleted: {
    reset()
    Qt.callLater(function() { timezoneField.forceActiveFocus() })
  }
  onServiceChanged: reset()

  Rectangle {
    anchors.fill: parent
    color: Color.popups.background
    border.width: Style.spacing.hairline
    border.color: Color.popups.border
    radius: Style.cornerRadius
  }

  Flickable {
    id: scroll
    anchors.fill: parent
    anchors.margins: Style.space(18)
    contentWidth: form.width
    contentHeight: form.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

    Column {
      id: form
      width: Math.max(scroll.width, Style.space(390))
      spacing: Style.space(9)

      Text {
        textFormat: Text.PlainText
        text: "Planner settings"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.display
        font.bold: true
      }
      Text {
        textFormat: Text.PlainText
        text: "Automatic proposals use only this local configuration."
        color: Qt.darker(root.foreground, 1.45)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text { textFormat: Text.PlainText; text: "Timezone"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
      TextField {
        id: timezoneField
        width: parent.width
        foreground: root.foreground
        font.family: root.fontFamily
        placeholderText: "Europe/Rome"
        Keys.onReturnPressed: root.save()
        Keys.onEscapePressed: root.cancelled()
      }
      Text {
        textFormat: Text.PlainText
        visible: timezoneField.text.trim() === "" && root.detectedTimezone() !== ""
        text: "Detected timezone: " + root.detectedTimezone() + " (suggestion; save to use)"
        color: Qt.darker(root.foreground, 1.45)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Row {
        width: parent.width
        spacing: Style.space(8)
        NumberField {
          width: (parent.width - Style.space(16)) / 3
          label: "Horizon days"
          value: root.horizonDays
          from: 1
          to: 90
          foreground: root.foreground
          onModified: root.horizonDays = value
        }
        NumberField {
          width: (parent.width - Style.space(16)) / 3
          label: "Slot minutes"
          value: root.slotMinutes
          from: 5
          to: 120
          foreground: root.foreground
          onModified: root.slotMinutes = value
        }
        NumberField {
          width: (parent.width - Style.space(16)) / 3
          label: "Solve seconds"
          value: root.solveSeconds
          from: 1
          to: 120
          foreground: root.foreground
          onModified: root.solveSeconds = value
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(8)
        Text {
          textFormat: Text.PlainText
          width: parent.width - availabilityButton.width - Style.space(8)
          text: availabilityCount() + " weekly availability window" + (availabilityCount() === 1 ? "" : "s")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          anchors.verticalCenter: parent.verticalCenter
        }
        Button {
          focusable: true
          id: availabilityButton
          text: "Edit availability"
          foreground: root.foreground
          bordered: true
          fontFamily: root.fontFamily
          onClicked: root.availabilityOpen = true
        }
      }

      Button {
        focusable: true
        text: root.advanced ? "Advanced settings  ▴" : "Advanced settings  ▾"
        foreground: root.foreground
        bordered: true
        fontFamily: root.fontFamily
        onClicked: root.advanced = !root.advanced
      }

      Column {
        visible: root.advanced
        width: parent.width
        spacing: Style.space(9)

        Text {
          textFormat: Text.PlainText
          text: "Priority weights"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }
        Row {
          width: parent.width
          spacing: Style.space(8)
          NumberField {
            width: (parent.width - Style.space(16)) / 3
            label: "Low"
            value: root.priorityLowWeight
            from: 0
            to: 100000
            foreground: root.foreground
            onModified: root.priorityLowWeight = value
          }
          NumberField {
            width: (parent.width - Style.space(16)) / 3
            label: "Normal"
            value: root.priorityNormalWeight
            from: 0
            to: 100000
            foreground: root.foreground
            onModified: root.priorityNormalWeight = value
          }
          NumberField {
            width: (parent.width - Style.space(16)) / 3
            label: "High"
            value: root.priorityHighWeight
            from: 0
            to: 100000
            foreground: root.foreground
            onModified: root.priorityHighWeight = value
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(8)
          Text {
            textFormat: Text.PlainText
            text: "Use cognitive-load timing preferences"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
          }
          ToggleSwitch {
            checked: root.cognitiveEnabled
            foreground: root.foreground
            onToggled: root.cognitiveEnabled = !root.cognitiveEnabled
          }
        }

        Text { textFormat: Text.PlainText; text: "Cognitive windows"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
        Row {
          width: parent.width
          spacing: Style.space(6)
          Text { textFormat: Text.PlainText; text: "Low"; width: Style.space(38); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
          TextField { id: lowStartField; width: Style.space(90); foreground: root.foreground; font.family: root.fontFamily; placeholderText: "00:00" }
          Text { textFormat: Text.PlainText; text: "—"; color: root.foreground; anchors.verticalCenter: parent.verticalCenter }
          TextField { id: lowEndField; width: Style.space(90); foreground: root.foreground; font.family: root.fontFamily; placeholderText: "00:00" }
          NumberField { width: Style.space(100); label: "Penalty"; value: root.lowOutsidePenalty; from: 0; to: 100000; foreground: root.foreground; onModified: root.lowOutsidePenalty = value }
        }
        Row {
          width: parent.width
          spacing: Style.space(6)
          Text { textFormat: Text.PlainText; text: "Medium"; width: Style.space(38); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
          TextField { id: mediumStartField; width: Style.space(90); foreground: root.foreground; font.family: root.fontFamily; placeholderText: "00:00" }
          Text { textFormat: Text.PlainText; text: "—"; color: root.foreground; anchors.verticalCenter: parent.verticalCenter }
          TextField { id: mediumEndField; width: Style.space(90); foreground: root.foreground; font.family: root.fontFamily; placeholderText: "00:00" }
          NumberField { width: Style.space(100); label: "Penalty"; value: root.mediumOutsidePenalty; from: 0; to: 100000; foreground: root.foreground; onModified: root.mediumOutsidePenalty = value }
        }
        Row {
          width: parent.width
          spacing: Style.space(6)
          Text { textFormat: Text.PlainText; text: "High"; width: Style.space(38); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
          TextField { id: highStartField; width: Style.space(90); foreground: root.foreground; font.family: root.fontFamily; placeholderText: "00:00" }
          Text { textFormat: Text.PlainText; text: "—"; color: root.foreground; anchors.verticalCenter: parent.verticalCenter }
          TextField { id: highEndField; width: Style.space(90); foreground: root.foreground; font.family: root.fontFamily; placeholderText: "00:00" }
          NumberField { width: Style.space(100); label: "Penalty"; value: root.highOutsidePenalty; from: 0; to: 100000; foreground: root.foreground; onModified: root.highOutsidePenalty = value }
        }

        Text { textFormat: Text.PlainText; text: "Recovery"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
        Row {
          width: parent.width
          spacing: Style.space(8)
          NumberField { width: (parent.width - Style.space(16)) / 3; label: "High streak limit"; value: root.highStreakLimit; from: 1; to: 100; foreground: root.foreground; onModified: root.highStreakLimit = value }
          NumberField { width: (parent.width - Style.space(16)) / 3; label: "Recovery minutes"; value: root.recoveryMinutes; from: 0; to: 1440; foreground: root.foreground; onModified: root.recoveryMinutes = value }
          NumberField { width: (parent.width - Style.space(16)) / 3; label: "Excess penalty"; value: root.excessHighPenalty; from: 0; to: 100000; foreground: root.foreground; onModified: root.excessHighPenalty = value }
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: root.errorText !== ""
        text: root.errorText
        color: Color.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
        width: parent.width
      }

      Row {
        spacing: Style.space(8)
        Button {
          focusable: true
          text: "Save settings"
          foreground: Color.background
          background: Color.accent
          fontFamily: root.fontFamily
          onClicked: root.save()
        }
        Button {
          focusable: true
          text: "Cancel"
          foreground: root.foreground
          bordered: true
          fontFamily: root.fontFamily
          onClicked: root.cancelled()
        }
      }
    }
  }

  Loader {
    id: availabilityLoader
    anchors.fill: parent
    active: root.availabilityOpen
    source: Qt.resolvedUrl("AvailabilityEditor.qml")
    onLoaded: {
      item.service = root.service
      item.bar = root.bar
    }
  }

  Connections {
    target: availabilityLoader.item
    function onSaved() {
      root.availabilityOpen = false
      root.reset()
    }
    function onCancelled() { root.availabilityOpen = false }
  }
}
