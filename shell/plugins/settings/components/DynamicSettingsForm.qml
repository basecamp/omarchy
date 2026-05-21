import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui as Ui

Column {
  id: root

  signal fieldChanged(string key, var value)

  property var schema: []
  property var entry: ({})
  property color foreground: Color.popups.text
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  // Resolved on disk path of the plugin that owns this form, used to
  // resolve relative argv entries in a multiselect's `optionsCommand`.
  property string pluginSourceDir: ""

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
    case "multiselect": return []
    default: return ""
    }
  }

  // Resolve a multiselect's optionsCommand argv against the plugin's source
  // directory. The first entry is treated as a path relative to the plugin
  // dir unless it is absolute or begins with ".". Subsequent entries pass
  // through unchanged.
  // Resolve a multiselect's optionsCommand argv against the plugin's source
  // directory. The first argv entry must be a relative path inside the
  // plugin dir (no leading `/`, no `..` segments, no empty segments);
  // anything else is rejected and the field falls back to whatever static
  // `options` it has. Subsequent argv entries pass through unchanged. We
  // avoid `Array.isArray` because schema-supplied arrays sometimes arrive
  // as QML JSValue lists that don't satisfy it; iterating by `.length`
  // works for both real arrays and JSValue lists.
  function resolveOptionsCommand(field) {
    var oc = field ? field.optionsCommand : undefined
    if (!oc || typeof oc.length !== "number" || oc.length === 0) return []
    var argv = []
    for (var i = 0; i < oc.length; i++) argv.push(String(oc[i]))
    if (!pluginSourceDir) return []
    var head = argv[0]
    if (head.length === 0 || head.charAt(0) === "/") {
      console.warn("DynamicSettingsForm: optionsCommand must be a path relative to the plugin dir, got: " + head)
      return []
    }
    var rel = head.replace(/^\.\//, "")
    var segments = rel.split("/")
    for (var s = 0; s < segments.length; s++) {
      if (segments[s] === ".." || segments[s] === "") {
        console.warn("DynamicSettingsForm: optionsCommand may not contain '..' or empty segments: " + head)
        return []
      }
    }
    var dir = pluginSourceDir.replace(/\/$/, "")
    argv[0] = dir + "/" + rel
    return argv
  }

  Repeater {
    model: root.schema

    Column {
      required property var modelData

      width: root.width
      spacing: Style.spacing.labelGap

      Text {
        visible: text !== ""
        text: modelData && modelData.label ? modelData.label : (modelData && modelData.key ? modelData.key : "")
        color: Qt.darker(root.foreground, 1.3)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      Text {
        visible: !!(modelData && modelData.description)
        text: modelData ? (modelData.description || "") : ""
        color: Qt.darker(root.foreground, 1.6)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        width: parent.width
      }

      Loader {
        width: parent.width
        height: item ? item.implicitHeight : 0
        sourceComponent: {
          if (!modelData || !modelData.type) return stringField
          switch (String(modelData.type)) {
          case "boolean": return booleanField
          case "enum": return enumField
          case "integer": return integerField
          case "number": return numberField
          case "multiselect": return multiselectField
          default: return stringField
          }
        }
        onLoaded: {
          if (!item) return
          item.fieldKey = modelData.key
          item.field = modelData
        }
      }
    }
  }

  Text {
    visible: !root.schema || root.schema.length === 0
    text: "No settings."
    color: Qt.darker(root.foreground, 1.5)
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Component {
    id: stringField

    Ui.TextField {
      property string fieldKey: ""
      property var field: ({})

      width: parent.width
      foreground: root.foreground
      accent: root.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      text: root.currentValue(field) === undefined ? "" : String(root.currentValue(field))

      onEditingFinished: if (fieldKey) root.fieldChanged(fieldKey, text)
    }
  }

  Component {
    id: booleanField

    Ui.Toggle {
      property string fieldKey: ""
      property var field: ({})

      width: parent.width
      label: "Enabled"
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      checked: !!root.currentValue(field)

      onClicked: if (fieldKey) root.fieldChanged(fieldKey, !checked)
    }
  }

  Component {
    id: enumField

    Ui.Dropdown {
      property string fieldKey: ""
      property var field: ({})

      width: parent.width
      showLabel: false
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      options: field && field.options ? field.options : []
      value: String(root.currentValue(field))

      onChanged: function(value) {
        if (fieldKey) root.fieldChanged(fieldKey, value)
      }
    }
  }

  Component {
    id: integerField

    Ui.NumberField {
      property string fieldKey: ""
      property var field: ({})

      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      from: field && field.min !== undefined ? field.min : 0
      to: field && field.max !== undefined ? field.max : 9999
      stepSize: field && field.step !== undefined ? field.step : 1
      value: {
        var v = root.currentValue(field)
        var n = typeof v === "number" ? v : parseInt(String(v || 0), 10)
        return isFinite(n) ? n : 0
      }

      onModified: function(value) { if (fieldKey) root.fieldChanged(fieldKey, value) }
    }
  }

  Component {
    id: multiselectField

    Ui.MultiSelect {
      property string fieldKey: ""
      property var field: ({})

      width: parent.width
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      showLabel: false
      // MultiSelect's arrayFrom() tolerates JSValue-style schema arrays, so
      // we can hand it `field.options` directly without an Array.isArray
      // guard that would silently drop JSValue lists.
      options: field ? (field.options || []) : []
      optionsCommand: root.resolveOptionsCommand(field)
      optionsCommandCwd: root.pluginSourceDir
      placeholderText: field && field.placeholderText ? String(field.placeholderText) : "Search..."
      emptyText: field && field.emptyText ? String(field.emptyText) : "No options"
      noSelectionText: field && field.noSelectionText ? String(field.noSelectionText) : "None selected"
      values: {
        var v = root.currentValue(field)
        return v ? v : []
      }

      onChanged: function(arr) { if (fieldKey) root.fieldChanged(fieldKey, arr) }
    }
  }

  Component {
    id: numberField

    Row {
      property string fieldKey: ""
      property var field: ({})
      property real currentNumber: {
        var v = root.currentValue(field)
        var n = typeof v === "number" ? v : parseFloat(String(v || 0))
        return isFinite(n) ? n : 0
      }

      width: parent.width
      spacing: Style.spacing.rowGap

      QQC.Slider {
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
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }
}
