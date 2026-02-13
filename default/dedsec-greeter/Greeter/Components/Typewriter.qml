import QtQuick

Text {
    id: root
    required property string initialText
    property int charIndex: 0

    property string nextText

    text: nextText.substr(0, charIndex) + initialText.substr(charIndex, initialText.length)

    SequentialAnimation {
        id: overwriteAnimation

        NumberAnimation {
            target: root
            property: "charIndex"
            duration: root.initialText.length * 60
            to: root.initialText.length
            easing.type: Easing.InSine
        }
    }

    function overwrite(s: string) {
        // TODO basic implementation only works when next is smaller than initial text
        const initialLength = root.initialText.length;
        const nextLength = s.length;

        const pad = (initialLength - nextLength) / 2;

        const lPad = Math.floor(pad);
        const rPad = Number.isInteger(pad) ? lPad : lPad + 1;

        root.nextText = `${" ".repeat(lPad)}${s}${" ".repeat(rPad)}`;

        overwriteAnimation.start();
    }
}
