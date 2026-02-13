import QtQuick
import QtQuick.Layouts

import "../Common"
import "../Config"

Surface {
    id: root
    margins: 18
    barColor: Qt.darker(Theme.textPrimaryDimmer, 2)
    topMargin: 14
    bottomMargin: 14

    component InfoField: ColumnLayout {
        id: field
        property string label: "FIELD"
        property string value: "VALUE"
        property alias fieldValueOpacity: fieldValue.opacity

        Text {
            id: fieldLabel
            text: field.label
            color: Theme.textPrimaryDim
            font {
                family: Settings.fontFamily
                pixelSize: 12
            }
        }

        Text {
            id: fieldValue
            text: field.value
            color: Theme.textPrimary
            font {
                family: Settings.fontFamily
                pixelSize: 18
                weight: 500
            }
        }
    }

    ColumnLayout {
        spacing: 10

        RowLayout {
            id: row
            spacing: 30

            InfoField {
                Layout.fillWidth: true
                label: "ENV"
                value: Settings.systemInfo.env
            }

            InfoField {
                Layout.fillWidth: true
                label: "NODE"
                value: Settings.systemInfo.node
            }
        }
    }
}
