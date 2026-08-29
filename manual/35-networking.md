# Networking

Networking in Omarchy is handled by NetworkManager, and you drive it from the network icon in the [top bar](05-the-top-bar.md) or with `Super + Ctrl + W`.

That panel scans for Wi-Fi networks, shows signal strength, and connects. Ethernet needs nothing at all — plug it in and it works. If you'd rather stay in the terminal, `nmtui` gives you the same controls, and there's an `omarchy network` command group too.

## Sharing your Wi-Fi

Rather than reading a long password out loud, run _Setup > Network > QR Code_ while you're on Wi-Fi. That puts a QR code on screen that any phone camera can scan to join. It's one of those things you'll use more than you'd expect once you know it's there.

If you actually need the password itself, `omarchy network password <interface>` prints it.

## Hosting a hotspot

You can turn this machine into a Wi-Fi access point that other devices join and route through your internet. Open the network panel (_Super + Ctrl + W_), scroll to the **HOTSPOT** section, and flip the switch. The first time it asks for your permission once — through the system password prompt — to open the firewall rules a shared connection needs.

Give the hotspot a name and a password by pressing the gear next to the toggle. The checkmark saves them without starting, the eye reveals the password, and the dice rolls you a random one. Credentials live in NetworkManager, not in a config file. Most adapters serve a single band and get no choice; when yours can do several, a band row appears next to the toggle.

A hotspot runs on the Wi-Fi radio, so the internet it shares has to come from somewhere else — plug in ethernet or share your phone's connection. The panel warns when there's no such upstream, but a LAN-only hotspot still works.

From the terminal it's `omarchy hotspot toggle`, or `omarchy hotspot start <ssid> <band>` with the password typed in after. `omarchy hotspot qr` prints a scannable join code, and _Trigger > Wi-Fi Hotspot_ in the menu toggles it too.

## DNS

Omarchy uses whatever DNS your network hands out over DHCP. You can override that for the whole machine under _Setup > Network > DNS_, where Cloudflare and Google are one click away. Pick _Custom_ to type in your own servers.

From the terminal, `omarchy dns` prints the current provider and `omarchy dns Cloudflare` sets one.

## Pinning the Wi-Fi band

If your router puts 2.4GHz, 5GHz, and 6GHz on the same network name, your laptop will sometimes cling to the slow one. `omarchy network band` shows which band you're on, and `omarchy network band 5` pins it. Use `auto` to let it choose again.

This pins the band rather than a specific access point, so you keep roaming between APs normally.

## How fast is it?

_Trigger > Speed Test > Network Speed Test_ measures your actual up and down speed with a pair of dials. From the terminal it's `omarchy network speedtest down` or `up`. (There's a disk speed test sitting next to it in that menu, if you're benchmarking the other bottleneck.)

## The firewall

The firewall is on by default and blocks all incoming traffic, with one exception: port 53317, so [LocalSend](22-guis.md) works out of the box.

SSH is off until you turn it on with _Setup > Security > SSHD_, which starts the daemon, opens port 22 rate-limited against brute force, and authorizes a key. Docker is locked down too, so containers can't accidentally expose themselves to the world. See [security](48-security.md) for the whole story.

## Tailscale

[Tailscale](https://tailscale.com/) is a mesh VPN that makes reaching all your computers and servers over the internet simple and secure. Install it with _Install > Service > Tailscale_.

That gives you a Tailscale panel in the bar, which connects and disconnects the tailnet, switches accounts, and picks an exit node — your own machines and Mullvad regions both show up in the list. It also browses your machines, and that's where Taildrop lives: select a machine and press `s` to send it files, or `c`, `n`, and `d` to copy its IP, name, or full DNS name. The terminal equivalent is `omarchy tailscale send <machine> [file...]`, and files sent to you land in `~/Downloads` automatically. The notification announcing an arrival waits until you click it open or dismiss it, so a file that turns up while you're away from the machine is still there to answer when you get back.

Installing it also adds a web app for the Tailscale admin console.

## When it stops working

Before rebooting, try restarting the offending piece on its own. _Update > Hardware_ has Wi-Fi, Bluetooth, Audio, and Trackpad, and reloading one of those clears up most "it worked five minutes ago" situations. See [troubleshooting](45-troubleshooting.md).
