pragma Singleton
import QtQml

QtObject {
  enum Code {
    Success,
    Unknown,
    FileNotFound,
    PermissionDenied,
    NotAFile
  }

  function toString(value) {
    if (value === Success) return "success"
    if (value === FileNotFound) return "file not found"
    if (value === PermissionDenied) return "permission denied"
    if (value === NotAFile) return "not a file"
    return "unknown error"
  }
}
