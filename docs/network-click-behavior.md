# Network Click Behavior (Waybar)

Omarchy uses Waybar's `network` module for both Wi-Fi and Ethernet.
The module exposes a single click handler (`on-click`), so Omarchy's handler must work on:

- Wi-Fi only machines
- Ethernet only machines
- Machines with both
- Machines with no detected network adapter

## Implementation

Waybar calls `omarchy-launch-wifi`.

That script:

1. Detects whether a physical Wi-Fi adapter exists by checking `/sys/class/net/*` for:
   - a physical device (`/sys/class/net/<iface>/device` exists)
   - and Wi-Fi markers (`wireless/` directory or `phy80211` link)
2. If Wi-Fi exists, it launches the Wi-Fi TUI (`impala`).
3. If Wi-Fi does not exist but a physical non-Wi-Fi adapter does, it launches an Ethernet status screen.
4. If neither exists, it shows a notification ("No Network Adapter Found").

This avoids launching Wi-Fi tooling on Ethernet-only hardware, which is a common setup for desktops and VMs.

