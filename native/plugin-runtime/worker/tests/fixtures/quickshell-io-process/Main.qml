import QtQuick
import Quickshell.Io 1.0

Item {
  Process { command: ["/bin/sh", "-c", "id"] }
}
