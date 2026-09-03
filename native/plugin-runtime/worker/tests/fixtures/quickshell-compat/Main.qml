import QtQuick
import Quickshell 1.0
import Quickshell.Widgets 1.0

Item {
  id: root
  objectName: clock.date instanceof Date
    && scope.children.length === 1
    && singleton.children.length === 1
    && lazy.item !== null
    && wrapper.child !== null
    && wrapper.child.x === 3
    && shell.reloadableId === "worker-root"
    ? "quickshell-compat-loaded" : "quickshell-compat-incomplete"

  ShellRoot {
    id: shell
    reloadableId: "worker-root"
    visible: false
    Rectangle { width: 1; height: 1 }
  }

  Scope {
    id: scope
    QtObject {}
  }

  Singleton {
    id: singleton
    QtObject {}
  }

  SystemClock { id: clock; enabled: false }

  LazyLoader {
    id: lazy
    active: true
    Rectangle { width: 2; height: 2 }
  }

  WrapperItem {
    id: wrapper
    width: 20
    height: 20
    margin: 3
    Rectangle { implicitWidth: 5; implicitHeight: 5 }
  }

  WrapperMouseArea {
    margin: 1
    Rectangle { implicitWidth: 4; implicitHeight: 4 }
  }

  WrapperRectangle {
    margin: 2
    Rectangle { implicitWidth: 4; implicitHeight: 4 }
  }

  IconImage { implicitSize: 16 }
}
