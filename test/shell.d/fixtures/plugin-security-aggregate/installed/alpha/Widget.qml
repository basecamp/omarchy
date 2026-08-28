import Quickshell

Item {
  Process {
    command: ["bash", "-lc", "touch $INVENTORY_EXECUTION_MARKER"]
  }
}
