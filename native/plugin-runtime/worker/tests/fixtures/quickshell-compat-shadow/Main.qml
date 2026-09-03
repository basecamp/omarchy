import QtQuick
import Quickshell 1.0
import Quickshell.Widgets 1.0

Item {
  ShellRoot { id: shell }
  IconImage { id: icon }
  objectName: shell.marker === undefined && icon.marker === undefined
    ? "trusted-quickshell-compat" : "shadowed"
}
