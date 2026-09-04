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

## Feeds

Feeds is Omarchy's finite, algorithm-free reading inbox, powered by [Newsboat](https://newsboat.org/). Install it from _Install > Feeds_ in the Omarchy menu, or run `omarchy install newsboat`. Launch it later from the app menu or with `omarchy feeds`. It follows the active terminal theme and starts with useful Omarchy and Arch Linux sources.

Opening Feeds collects one fresh edition before showing it. Nothing else arrives until you explicitly refresh with `r`, so the unread Inbox is something you can finish rather than an endless stream. Reach zero and Omarchy sends one quiet confirmation: you're all caught up; go make something.

The easiest way to subscribe is to visit a page in a Chromium-family browser and press `Alt + Shift + F`. Omarchy discovers the RSS or Atom address advertised by that page and confirms the subscription. You can also copy a page URL and choose _Trigger > Feeds > Subscribe URL_, or discover it from the terminal:

```bash
omarchy newsboat subscribe https://world.hey.com/dhh
```

Use `j` and `k` to move, `l` or `Return` to open a feed or article, `h` to go back, `r` to collect another edition, `o` to open an article in your browser, and `q` to quit. Press `?` for Newsboat's complete keybinding list.

When an article is selected, press `,a` to send that article to your configured default Omarchy agent. Press `,b` to brief the whole unread edition: the agent groups duplicate coverage, recommends at most three worthwhile reads, and says what can safely be skipped. It then asks whether it should mark the skipped articles as read and leave its recommendations waiting for you. After you agree in the conversation, Omarchy opens its own confirmation window with the exact numbers; nothing changes until you approve that separate prompt.

Press `,d` on an interesting article to open Feed Scout with that context. From the feed list (including Inbox), the same keys look for gaps across all your subscriptions; _Trigger > Feeds > Feed Scout_ does the same. The configured agent researches a maximum of five high-signal sources, resolves and validates their real RSS or Atom documents, explains why each belongs, and asks exactly how many to add. It cannot silently subscribe: only the opaque feed IDs from that one-use proposal are accepted, and Omarchy requires approval in a separate confirmation window before applying them. You can also give Scout a subject from the terminal:

```bash
omarchy newsboat scout "independent Ruby writing"
```

Brief uses bounded excerpts already cached in Newsboat and does not fetch article pages. Articles without usable cached text, and those outside the briefing's content budget, stay unread. The agent should explain uncertainty and leave anything it cannot confidently assess for you to read.

All agent actions use whichever Omarchy agent you chose; if no default is configured, Omarchy shows a notification linking to the agent picker.

Subscriptions can be managed from the terminal:

```bash
omarchy newsboat add https://example.com/feed.xml
omarchy newsboat remove https://example.com/feed.xml
omarchy newsboat edit
```

`add` and `remove` expect an exact RSS or Atom address, while `subscribe` accepts an ordinary webpage and discovers its feed. `edit` opens `~/.config/newsboat/urls` in your configured editor, which is also where you can add Newsboat tags after an address.

To migrate subscriptions from another reader, export an OPML file there and import it into Newsboat. Import merges those subscriptions with the feeds you already have:

```bash
omarchy newsboat import ~/Downloads/subscriptions.opml
```

You can create an OPML backup or move to another reader without overwriting an existing file:

```bash
omarchy newsboat export ~/Downloads/newsboat-subscriptions.opml
```

Personal Newsboat settings belong in `~/.config/newsboat/config`, below the Omarchy include. Omarchy maintains `~/.config/newsboat/omarchy.conf`; keeping the two layers separate lets integration improvements arrive with normal Omarchy updates without replacing personal settings.

## What about Wi-Fi and Bluetooth?

You won't find TUIs for Wi-Fi and Bluetooth — those jobs belong to the Omarchy shell. Click the Wi-Fi icon in the top bar (or hit `Super + Ctrl + W`) to see networks and connect, and click the Bluetooth icon (or hit `Super + Ctrl + B`) to pair and connect devices. See [networking](35-networking.md) for the full story.

## Adding your own

Any terminal program can get the full app treatment. Go to _Install > TUI_ in the Omarchy menu (`Super + Space`), give it a name, a launch command, a window style, and an icon, and it'll show up in the app launcher like any other application. You can remove it again under _Remove > TUI_.
