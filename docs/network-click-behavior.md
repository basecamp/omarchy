# Network Click Behavior (Waybar)

Omarchy uses Waybar's `network` module for both Wi-Fi and Ethernet.
That module exposes a single click handler, so Omarchy routes the action to one unified network TUI.

## Implementation

Waybar calls `omarchy-launch-wifi`.

That launcher opens `nettui`.

`nettui` is responsible for:

1. showing Wi-Fi and Ethernet in one TUI
2. handling Wi-Fi-only systems
3. handling Ethernet-only systems
4. handling systems with both adapters present
5. showing a clear state when no adapter is available

If `nettui` is not installed, the launcher shows a notification instead of opening a partial fallback UI.
