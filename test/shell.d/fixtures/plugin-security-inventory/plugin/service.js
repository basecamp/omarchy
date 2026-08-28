function refresh(endpoint) {
  Quickshell.execDetached(["curl", endpoint])
}

function moveWorkspace(workspace) {
  Quickshell.execDetached(["hyprctl", "dispatch", "workspace", workspace])
}
