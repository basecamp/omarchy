import QtQuick
import QtQuick.Layouts 6.0

Item {
    objectName: "trusted-layouts"

    RowLayout {
        Rectangle { Layout.preferredWidth: 12 }
        Rectangle { Layout.fillWidth: true }
    }
}
