# Hotkeys

You can see all the main keyboard bindings with `Super + K`.

## Navigating

| Hotkey                  | Function              |
| ----------------------- | --------------------- |
| `Super + Space`           | Application launcher    |
| `Super + Alt + Space` | Omarchy control menu |
| `Super + Escape` | System menu (suspend, restart, etc)  |
| `Super + Ctrl + L` | Lock computer |
| `Super + W`               | Close window             |
| `Ctrl + Alt + Del` | Close all windows |
| `Super + T`               | Toggle window between tiling/floating             |
| `Super + J` | Toggle window position (horizontal/vertical) |
| `Super + O`               | Toggle popping window into sticky'n'floating |
| `Super + L`               | Toggle between dwindle and scrolling layout |
| `Super + P`               | Toggle pseudo window style (natural v stretch) |
| `Super + F`                 | Go full screen              |
| `Super + Alt + F`                 | Go full width              |
| `Super + Ctrl + F`                 | Go full screen inside window              |
| `Super + 1/2/3/4`         | Jump to specific workspace     |
| `Super + Tab` | Jump to next workspace |
| `Super + Shift + Tab` | Jump to previous workspace |
| `Super + Ctrl + Tab` | Jump to former workspace |
| `Super + Shift + 1/2/3/4` | Move window to workspace |
| `Super + Shift + Alt + 1/2/3/4` | Move window to workspace without following |
| `Super + Shift + Alt + Arrows` | Move workspaces to directional monitor |
| `Super + Arrow`  | Move focus to window in direction of arrow              |
| `Super + Shift + Arrow`  | Swap window with another in direction of arrow     |
| `Super + Equal` | Grow windows to the left |
| `Super + Minus` | Grow windows to the right |
| `Super + Shift + Equal` | Grow windows to the bottom |
| `Super + Shift + Minus` | Grow windows to the top |
| `Super + Left Mouse` | Drag window around |
| `Super + Right Mouse` | Resize window |
| `Super + Scroll Wheel` | Scroll through workspaces |
| `Super + G`               | Toggle window grouping      |
| `Super + Alt + G`               | Move window out of grouping      |
| `Super + Alt + Tab`               | Cycle between windows in grouping      |
| `Super + Alt + 1/2/3/4`               | Jump to specific window in grouping      |
| `Super + Alt + Arrow`  | Move window into grouping in direction of arrow  |
| `Super + Ctrl + Arrow`  | Move between windows inside a tiling group |
| `Super + S` | Show scratchpad workspace overlay |
| `Super + Alt + S` | Move window to scratchpad workspace |
| `Super + Ctrl + Z` | Zoom in on screen (repeat for more zoom) |
| `Super + Ctrl + Alt + Z` | Zoom fully out from screen |
| `Super + /` | Cycle forward through monitor scaling options |
| `Super + Alt + /` | Cycle backward through monitor scaling options |
| `Alt + Tab` | Cycle forward through windows on the active workspace |
| `Alt + Shift + Tab` | Cycle backward through windows on the active workspace |
| `Ctrl + Alt + Tab`| Cycle focus forward through monitors |
| `Ctrl + Alt + Shift + Tab`| Cycle focus backwards through monitors |

## System controls

| Hotkey                  | Function              |
| ----------------------- | --------------------- |
| `Super + Ctrl + A`           | Audio controls (wiremix)    |
| `Super + Ctrl + B`           | Bluetooth controls (bluetui)    |
| `Super + Ctrl + W`           | Wifi controls (impala)    |
| `Super + Ctrl + S` | Share menu (via LocalSend) |
| `Super + Ctrl + T`           | Activity (btop)    |
| `Super + Ctrl + C` | Capture controls (screenshot/-recording/picker) |
| `Super + Ctrl + O` | Toggle menu |
| `Super + Ctrl + H` | Hardware menu |
| `Super + Ctrl + .` | Transcoding menu |

## Adjustments

| Hotkey                  | Function              |
| ----------------------- | --------------------- |
| `Shift + Brightness Up` | Maximum screen brightness |
| `Shift + Brightness Up` | Minimum screen brightness |
| `Alt + Brightness Up/Down` | Precise 1% brightness changes |
| `Alt + Volume Up/Down` | Precise 1% volume changes |

## Launching apps

| Hotkey                  | Function              |
| ----------------------- | --------------------- |
| `Super + Return`           | Terminal    |
| `Super + Alt + Return` | Tmux terminal |
| `Super + Shift + Return`           | Browser    |
| `Super + Shift + Alt + B`           | Browser (private/incognito)    |
| `Super + Shift + F`           | File manager    |
| `Super + Shift + Alt + F`           | File manager in cwd of terminal    |
| `Super + Shift + M`           | Music (Spotify)    |
| `Super + Shift + Alt + M`           | Music (cliamp)    |
| `Super + Shift + /`           | Password manager (1password)    |
| `Super + Shift + N`           | Neovim  |
| `Super + Shift + C`           | Calendar ([HEY](https://hey.com/))  |
| `Super + Shift + E`           | Email ([HEY](https://hey.com/))  |
| `Super + Shift + A`           | AI (ChatGPT)  |
| `Super + Shift + Alt + A`           | AI (Grok)  |
| `Super + Shift + G`           | Messenger (Signal)  |
| `Super + Shift + P`           | Google Photos  |
| `Super + Shift + Alt + G`           | Messenger (WhatsApp)  |
| `Super + Shift + Ctrl + G`           | Messenger (Google)  |
| `Super + Shift + D`           | Docker (LazyDocker)  |
| `Super + Shift + O`           | Obsidian  |
| `Super + Shift + W`           | Writing (Typora)  |
| `Super + Shift + X`           | X |
| `Super + Shift + Alt + X`           | X Compose |
| `Super + Shift + Y`           | YouTube |

Change/add bindings in `~/.config/hypr/bindings.conf`.

## Universal clipboard

| Hotkey                  | Function              |
| ----------------------- | --------------------- |
| `Super + C`           | Copy    |
| `Super + X`           | Cut (not in terminal)    |
| `Super + V`           | Paste    |
| `Super + Ctrl + V`           | Clipboard manager    |

Usually on Linux, you need `Ctrl + Shift + C/V` to copy'n'paste in the terminal and `Ctrl + C/V` to do it everywhere else. These Omarchy unified clipboard hotkeys work everywhere (except the file manager).

## Capture

| Hotkey              | Function                       |
| ------------------- | ------------------------------ |
| `Super + Ctrl + C` | Capture menu (for keyboards w/o PrintScr button) |
| `Print Screen`            | Screenshot                      |
| `Alt + Print Screen`            | Screenrecord                     |
| `Super + Print Screen` | Color picker |
| `Super + Ctrl + Print Screen` | Text extraction to clipboard |
| `Alt + Shift + L` | Copy current URL from webapp or Chromium |
| `Super + Ctrl + X` | Start/stop dictation (requires _Install > AI > Dictation_) |
| `F9` | Push-to-talk dictation (requires _Install > AI > Dictation_) |

With screenrecordings, hit the hotkey to start, hit it again to stop.

All capture options are also accessible under _Capture_ in the Omarchy menu (`Super + Alt + Space`).

## Notifications

| Hotkey                  | Function              |
| ----------------------- | --------------------- |
| `Super + ,` | Dismiss latest notification  |
| `Super + Shift + ,` | Dismiss all notifications |
| `Super + Ctrl + ,` | Toggle silencing notifications  |
| `Super + Alt + ,` | Invoke most recent notification  |

## Style

| Hotkey                  | Function              |
| ----------------------- | --------------------- |
| `Super + Ctrl + Shift + Space` | Pick a new theme  |
| `Super + Ctrl + Space` | Pick theme background |
| `Super + Backspace` | Toggle transparency on a window |
| `Super + Ctrl + Backspace` | Toggle single-window square aspect |

Extra background images live in `~/.config/omarchy/current/backgrounds`. Also available via _Install > Background_ in the Omarchy menu.

All style options are also accessible under _Style_ in the Omarchy menu (`Super + Alt + Space`).

## Toggles

| Hotkey                  | Function              |
| ----------------------- | --------------------- |
| `Super + Ctrl + I` | Toggle idle/sleep prevention |
| `Super + Ctrl + N` | Toggle nightlight display temperature |
| `Super + Ctrl + Delete` | Toggle laptop display on/off |
| `Super + Ctrl + Alt + Delete` | Toggle laptop display mirroring |
| `Super + Shift + Space` | Toggle the top bar  |
| `Super + Mute` | Switch to next audio output |
| `Super + Shift + Backspace` | Toggle window gaps |

## Reminders

| Hotkey                  | Function              |
| ----------------------- | --------------------- |
| `Super + Ctrl + R` | Set a reminder  |
| `Super + Ctrl + Alt + R` | See all reminders  |
| `Super + Ctrl + Shift + R` | Clear all reminders  |

## Notices

| Hotkey                  | Function              |
| ----------------------- | --------------------- |
| `Super + Ctrl + Alt + T` | Show time as notification  |
| `Super + Ctrl + Alt + B` | Show battery as notification  |
| `Super + Ctrl + Alt + W` | Show weather as notification  |

## Tmux

The prefix key is `Ctrl + Space` (`Ctrl + B` also works). You can change these bindings in `~/.config/tmux/tmux.conf`.

### Panes

| Hotkey                  | Function              |
| ----------------------- | --------------------- |
| `Prefix + v` | Split pane beside (vertical) |
| `Prefix + h` | Split pane below (horizontal) |
| `Prefix + x` | Kill pane |
| `Prefix + z` | Toggle pane zoom (fullscreen) |
| `Ctrl + Alt + Arrows` | Move between panes |
| `Ctrl + Alt + Shift + Arrows` | Resize panes |

### Windows

| Hotkey                  | Function              |
| ----------------------- | --------------------- |
| `Prefix + c` | New window |
| `Prefix + k` | Kill window |
| `Prefix + r` | Rename window |
| `Alt + 1-9` | Go to specific window |
| `Alt + Arrow Left/Right` | Move between windows |

### Sessions

| Hotkey                  | Function              |
| ----------------------- | --------------------- |
| `Prefix + C` | New session |
| `Prefix + K` | Kill session |
| `Prefix + R` | Rename session |
| `Prefix + N` | Next session |
| `Prefix + P` | Previous session |
| `Alt + Arrow Up/Down` | Move between sessions |
| `Prefix + s` | List sessions |
| `Prefix + d` | Detach from session |

### Copy mode (vi-style)

| Hotkey                  | Function              |
| ----------------------- | --------------------- |
| `Prefix + [` | Enter copy mode |
| `v` | Begin selection (in copy mode) |
| `y` | Copy selection (in copy mode) |

### General

| Hotkey                  | Function              |
| ----------------------- | --------------------- |
| `Prefix + q` | Reload config |
| `Prefix + :` | Command prompt |

### Tmux layout functions

These functions must be run inside a Tmux session.

| Command | Function |
| ------- | -------- |
| `tdl <ai> [<second_ai>]` | Create dev layout with editor, AI, and terminal |
| `tdlm <ai> [<second_ai>]` | Create dev layout per subdirectory |
| `tsl <count> <command>` | Create multi-pane swarm layout |

## Ghostty Terminal

Ghostty terminal is installed using _Install > Terminal_ via the Omarchy menu.

| Hotkey                  | Function              |
| ----------------------- | --------------------- |
| `Ctrl + Shift + E` | New split below |
| `Ctrl + Shift + O` | New split besides |
| `Ctrl + Alt + Arrows` | Move between splits |
| `Super + Ctrl + Shift + Arrows` | Resize split by 10 lines |
| `Super + Ctrl + Shift + Alt + Arrows` | Resize split by 100 lines |
| `Ctrl + Shift + T` | New tab  |
| `Ctrl + Shift + Arrows` | Move between tabs tab |
| `Alt + Numbers` | Go to specific tab |
| `Shift + Pg Up/Down` | Scroll the history |
| `Ctrl + Left mouse` | Open link in browser |

## File Manager

| Hotkey              | Function                       |
| ------------------- | ------------------------------ |
| `Ctrl + L`            | Go to path                     |
| `Space`               | Preview file (arrows navigate) |
| `Backspace`      | Go back one folder             |

## Neovim (w/ lazyvim)

### Navigation

| Hotkey                   | Function                        |
| ------------------------ | ------------------------------- |
| `Space`                    | Show command options            |
| `Space Space`              | Open file via fuzzy search      |
| `Space E`                  | Toggle sidebar                  |
| `Space G G`                | Show git controls               |
| `Space S G`                | Search file content             |
| `Ctrl + W W`               | Jump between sidebar and editor |
| `Ctrl + Left/right arrow`  | Change size of sidebar          |
| `Shift + H`                      | Go to left file tab             |
| `Shift + L`                      | Go to right file tab            |
| `Space B D`                | Close file tab                  |

### While in sidebar

| Hotkey                   | Function                        |
| ------------------------ | ------------------------------- |
| `A`                        | Add new file in parent dir      |
| `Shift + A`                | Add new subdir in parent dir    |
| `D`                        | Delete highlighted file/dir     |
| `M`                        | Move highlighted file/dir       |
| `R`                        | Rename highlighted file/dir     |
| `?`                        | Show help for all commands      |

[See all the Neovim hotkeys configured by LazyVim](https://www.lazyvim.org/keymaps).

## Quick Emojis

You can use `Super + Ctrl + E` to show a complete emoji picker that'll put the selection on the clipboard or you can use these quick access options.

| Hotkey       | EM | Clue       |
| ------------ | -- | ---------- |
| `CapsLock M S` | 😄 | smile      |
| `CapsLock M C` | 😂 | cry        |
| `CapsLock M L` | 😍 | love       |
| `CapsLock M V` | ✌️ | victory    |
| `CapsLock M H` | ❤️ | heart      |
| `CapsLock M Y` | 👍 | yes        |
| `CapsLock M N` | 👎 | no         |
| `CapsLock M F` | 🖕 | fuck       |
| `CapsLock M W` | 🤞 | wish       |
| `CapsLock M R` | 🤘 | rock       |
| `CapsLock M K` | 😘 | kiss       |
| `CapsLock M E` | 🙄 | eyeroll    |
| `CapsLock M P` | 🙏 | pray |
| `CapsLock M D` | 🤤 | drool      |
| `CapsLock M M` | 💰 | money      |
| `CapsLock M X` | 🎉 | xellebrate |
| `CapsLock M 1` | 💯 | 100%       |
| `CapsLock M T` | 🥂 | toast      |
| `CapsLock M O` |👌 | ok |
| `CapsLock M G` |👋 | greeting |
| `CapsLock M A` |💪 | arm |
| `CapsLock M B` |🤯 | blowing |

## Quick Completions
| Hotkey       | Completion       |
| ------------ |  ---------- |
| `CapsLock Space Space` | — (mdash)   |
| `CapsLock Space N` | Your name (as entered on setup)  |
| `CapsLock Space E` | Your email (as entered on setup)  |

You can add more of your own by editing `~/.XCompose`, then running `omarchy-restart-xcompose` in the terminal to get the changes picked up.
