# TUIs

## Lazygit

[Lazygit](https://github.com/jesseduffield/lazygit) is a delightful alternative to something like the GitHub Desktop application, and it runs inside the terminal.

You can run it directly, by going to any directory managed by git and running `lazygit`. Or you can run it inside Neovim where it can be started with `Space G G`.

You hop between the different panes using `Tab`. In the Files pane, you select files for staging using `Space`, and then you can create a new commit using `c`. You can see all the commands available using `?`.

## Lazydocker

[Lazydocker](https://github.com/jesseduffield/lazydocker) is made in the same spirit like Lazygit, and also gives you a terminal interface for managing your containers and images.

You can start it with `Super + Shift + D`.

You stop a container using `s` or start/restart it using `r`. See all commands using `?`.

## Btop

[Btop](https://github.com/aristocratos/btop) is a beautiful resource manager that shows memory, CPU, disk, and network usage. It also lists all active processes, and allows you to manage them.

Omarchy calls it Activity, and you start it by hitting `Super + Ctrl + T`. It opens as a floating window, which you can tile with `Super + T`.

## Herdr

[Herdr](https://github.com/omacom-io/herdr) is a terminal workspace manager that gives you workspaces, tabs, and panes, and keeps them all running in a persistent session you can detach from and come back to later.

You start it (or reattach to your existing session) with `Super + Ctrl + Return`. Omarchy ships a Herdr configuration that mirrors its Tmux config, so the prefix key is `Ctrl + Space` here too. You can browse all the keybindings with `Super + Ctrl + K`.

## Fastfetch

[Fastfetch](https://github.com/fastfetch-cli/fastfetch) shows system information, like kernel version, uptime, theme, CPU, memory, and more. It's a successor to the popular neofetch tool.

Omarchy has packaged this as _About_ in the Omarchy menu (`Super + Space`).

## Disk Usage

When the drive fills up and you have no idea what's eating it, launch _Disk Usage_ from the app launcher (`Super + Space`). It's [dua](https://github.com/Byron/dua-cli) in interactive mode pointed at the whole file system, so you can walk down into whatever directory is the culprit, sorted biggest first, and delete from right inside it.

## Cliamp

[Cliamp](https://www.cliamp.stream/) is a retro terminal music player inspired by Winamp 2.x, complete with built-in radio stations for lo-fi beats. Launch it with `Super + Shift + Alt + M`, or from the Omarchy menu under _Apps_. Press `?` for the full keybinding list.

## What about Wi-Fi and Bluetooth?

You won't find TUIs for Wi-Fi and Bluetooth — those jobs belong to the Omarchy shell. Click the Wi-Fi icon in the top bar (or hit `Super + Ctrl + W`) to see networks and connect, and click the Bluetooth icon (or hit `Super + Ctrl + B`) to pair and connect devices. See [networking](35-networking.md) for the full story.

## Adding your own

Any terminal program can get the full app treatment. Go to _Install > TUI_ in the Omarchy menu (`Super + Space`), give it a name, a launch command, a window style, and an icon, and it'll show up in the app launcher like any other application. You can remove it again under _Remove > TUI_.
