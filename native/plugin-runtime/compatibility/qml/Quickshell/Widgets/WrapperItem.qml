import QtQuick

Item {
  id: root

  default property Item child
  property real margin: 0
  property real extraMargin: 0
  property real topMargin: margin
  property real bottomMargin: margin
  property real leftMargin: margin
  property real rightMargin: margin
  property bool resizeChild: true

  implicitWidth: child ? child.implicitWidth + leftMargin + rightMargin + 2 * extraMargin : 0
  implicitHeight: child ? child.implicitHeight + topMargin + bottomMargin + 2 * extraMargin : 0

  onChildChanged: if (child) child.parent = root

  Binding {
    target: root.child
    property: "x"
    value: root.leftMargin + root.extraMargin
    when: root.child !== null
  }

  Binding {
    target: root.child
    property: "y"
    value: root.topMargin + root.extraMargin
    when: root.child !== null
  }

  Binding {
    target: root.child
    property: "width"
    value: root.resizeChild
      ? Math.max(0, root.width - root.leftMargin - root.rightMargin - 2 * root.extraMargin)
      : root.child.implicitWidth
    when: root.child !== null
  }

  Binding {
    target: root.child
    property: "height"
    value: root.resizeChild
      ? Math.max(0, root.height - root.topMargin - root.bottomMargin - 2 * root.extraMargin)
      : root.child.implicitHeight
    when: root.child !== null
  }
}
