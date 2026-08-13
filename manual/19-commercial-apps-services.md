# Commercial apps/services

Omarchy is mostly focused on providing free, open source software, but it's not religious about it. Sometimes the best solution is a commercial offering, and that's just fine. Here are some of the options we provide an easy installation for.

## 1Password

Keeping your passwords in a password manager is a best practice. Doubly so if you're working with a team. And [1password](https://1password.com/) is a great solution, which also comes with a command line tool for integrating key lookups in scripts.

You start 1Password with `Super + Shift + /`. If it isn't installed yet, that hotkey kicks off the installation first (you can also use _Install > Service > 1Password_ from the Omarchy menu). The installer sets up the 1Password extension for Chromium as well.

## Spotify

[Spotify](https://spotify.com/) is the world's most popular streaming music service. And the Linux application provides everything you'd expect, including offline playing.

You start Spotify using `Super + Shift + M`. Like 1Password, the hotkey kicks off the installation first if Spotify isn't installed yet (or use _Install > Service > Spotify_ from the Omarchy menu).

## Dropbox

[Dropbox](https://www.dropbox.com/) is a great way to sync files between machines while keeping a backup in the cloud. To set it up, select _Install > Service > Dropbox_ from the Omarchy menu. Once it's running, hover the tray in the top right of the bar and right-click the Dropbox icon to finish the setup.

## Tailscale

[Tailscale](https://tailscale.com/) is a mesh VPN that makes getting access to all your computers and servers over the internet securely super simple way. To set it up, select _Install > Service > Tailscale_ from the Omarchy menu.

Installing it also puts a Tailscale indicator in the bar, adds a web app for the Tailscale admin console, and sets up Taildrop. That means you can send files between your machines with `omarchy tailscale send <machine> <file>`, and incoming files automatically land in `~/Downloads`.

## NordVPN

[NordVPN](https://nordvpn.com/) is a standard VPN service that lets you exit your traffic from most regions around the world. To set it up, select _Install > Service > NordVPN_ from the Omarchy menu. After the reboot it asks for, run `nordvpn login` to authenticate.
