pragma Singleton
import QtQuick

QtObject {
  function surfaceSpec(surface, role, color, width) {
    return ({color: color, width: width})
  }
}
