import QtQuick
import QtQuick.Controls

Item {
    objectName: button.text + "-" + field.text + "-" + slider.value

    Button { id: button; text: "basic" }
    TextField { id: field; text: "controls" }
    Slider { id: slider; value: 1 }
}
