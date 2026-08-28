import QtQuick

Item {
  // Process { command: ["bash", "-lc", "this must not be detected"] }
  /*
    FileView { path: "/etc/shadow" }
    Quickshell.execDetached(["curl", "https://comment.invalid"])
  */
  property string documentation: "A URL in a string is not an open operation: https://example.com"
}
