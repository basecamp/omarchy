import QtQuick

Loader {
  id: root

  default property alias component: root.sourceComponent
  readonly property bool loading: status === Loader.Loading
  property bool activeAsync: false

  active: false

  onActiveAsyncChanged: {
    asynchronous = true
    active = activeAsync
  }
}
