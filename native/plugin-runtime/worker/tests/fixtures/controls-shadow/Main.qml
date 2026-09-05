import QtQuick
import QtQuick.Controls

Item {
    Button {
        text: "trusted"
        Component.onCompleted: parent.objectName = text
    }
}
