import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// Generic schema-driven settings form. The host panel passes:
//   - schema: array of { key, label, type, defaultValue?, options?, min?, max?, step?, description? }
//   - entry:  current widget entry object (set by the loader); fields override defaults
//   - signal fieldChanged(string key, var value)  — emitted on user edits
//
// Supported types: boolean, enum, integer, number, string, path, command, color.
Column {
  id: root

  signal fieldChanged(string key, var value)

  property var schema: []
  property var entry: ({})
  property color foregroundColor: Color.foreground
  property string fontFamilyName: Style.font.family
  spacing: Style.spacing.xl
  width: parent ? parent.width : 0

  function currentValue(field) {
    if (entry && entry[field.key] !== undefined) return entry[field.key]
    if (field.defaultValue !== undefined) return field.defaultValue
    switch (field.type) {
    case "boolean": return false
    case "integer":
    case "number": return field.min !== undefined ? field.min : 0
    case "enum": return field.options && field.options.length > 0 ? field.options[0] : ""
    default: return ""
    }
  }

  Repeater {
    model: root.schema

    Column {
      required property var modelData
      width: root.width
      spacing: Style.spacing.labelGap

      Text {
        text: modelData && modelData.label ? modelData.label : (modelData && modelData.key ? modelData.key : "")
        color: Qt.darker(root.foregroundColor, 1.3)
        font.family: root.fontFamilyName
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        visible: text !== ""
      }

      Text {
        visible: !!(modelData && modelData.description)
        text: modelData ? (modelData.description || "") : ""
        color: Qt.darker(root.foregroundColor, 1.6)
        font.family: root.fontFamilyName
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        width: parent.width
      }

      Loader {
        sourceComponent: {
          if (!modelData || !modelData.type) return stringField
          switch (String(modelData.type)) {
          case "boolean": return booleanField
          case "enum": return enumField
          case "integer": return integerField
          case "number": return numberField
          case "color":
          case "string":
          case "path":
          case "command":
          default: return stringField
          }
        }
        onLoaded: if (item && "fieldKey" in item) {
          item.fieldKey = modelData.key
          item.field = modelData
        }
      }

      Component {
        id: stringField
        TextField {
          property string fieldKey: ""
          property var field: ({})
          width: parent.width
          foreground: root.foregroundColor
          font.family: root.fontFamilyName
          font.pixelSize: Style.font.body
          text: root.currentValue(field) === undefined ? "" : String(root.currentValue(field))
          onEditingFinished: if (fieldKey) root.fieldChanged(fieldKey, text)
        }
      }

      Component {
        id: booleanField
        CheckBox {
          property string fieldKey: ""
          property var field: ({})
          font.family: root.fontFamilyName
          font.pixelSize: Style.font.body
          text: field && field.label ? "" : ""
          checked: !!root.currentValue(field)
          onToggled: if (fieldKey) root.fieldChanged(fieldKey, checked)
        }
      }

      Component {
        id: enumField
        ComboBox {
          property string fieldKey: ""
          property var field: ({})
          width: parent.width
          font.family: root.fontFamilyName
          font.pixelSize: Style.font.body
          model: field && field.options ? field.options : []
          currentIndex: {
            var v = root.currentValue(field)
            for (var i = 0; i < (field && field.options ? field.options.length : 0); i++)
              if (field.options[i] === v) return i
            return 0
          }
          onActivated: function(index) {
            if (fieldKey && field && field.options) root.fieldChanged(fieldKey, field.options[index])
          }
        }
      }

      Component {
        id: integerField
        SpinBox {
          property string fieldKey: ""
          property var field: ({})
          from: field && field.min !== undefined ? field.min : 0
          to: field && field.max !== undefined ? field.max : 9999
          stepSize: field && field.step !== undefined ? field.step : 1
          value: {
            var v = root.currentValue(field)
            var n = typeof v === "number" ? v : parseInt(String(v || 0), 10)
            return isFinite(n) ? n : 0
          }
          onValueModified: if (fieldKey) root.fieldChanged(fieldKey, value)
        }
      }

      Component {
        id: numberField
        Row {
          property string fieldKey: ""
          property var field: ({})
          width: parent.width
          spacing: Style.spacing.rowGap
          property real currentNumber: {
            var v = root.currentValue(field)
            var n = typeof v === "number" ? v : parseFloat(String(v || 0))
            return isFinite(n) ? n : 0
          }
          Slider {
            id: slider
            width: parent.width - readout.width - Style.spacing.rowGap
            from: field && field.min !== undefined ? field.min : 0
            to: field && field.max !== undefined ? field.max : 1
            stepSize: field && field.step !== undefined ? field.step : 0.01
            value: parent.currentNumber
            onMoved: if (parent.fieldKey) root.fieldChanged(parent.fieldKey, value)
          }
          Text {
            id: readout
            text: slider.value.toFixed(2)
            color: root.foregroundColor
            font.family: root.fontFamilyName
            font.pixelSize: Style.font.bodySmall
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }
    }
  }

  Text {
    visible: !root.schema || root.schema.length === 0
    text: "No settings."
    color: Qt.darker(root.foregroundColor, 1.5)
    font.family: root.fontFamilyName
    font.pixelSize: Style.font.bodySmall
  }
}
