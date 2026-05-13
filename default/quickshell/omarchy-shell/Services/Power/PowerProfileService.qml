pragma Singleton
import QtQuick

// Noctalia compat shim. The "noctaliaPerformanceMode" flag was a v3 internal
// state Noctalia plugins occasionally check. We hardcode false; plugins that
// branch on it will fall into the non-performance code path.
QtObject {
  readonly property bool noctaliaPerformanceMode: false
}
