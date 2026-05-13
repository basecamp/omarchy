pragma Singleton
import QtQuick

// Noctalia compat shim.
QtObject {
  function getFormattedTimestamp() {
    return new Date().toISOString()
  }

  function nowMs() {
    return Date.now()
  }

  function formatDate(date, fmt) {
    if (!date) date = new Date()
    return Qt.formatDateTime(date, fmt || "yyyy-MM-dd HH:mm:ss")
  }
}
