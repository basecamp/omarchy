# Omarchy

Turn a fresh Arch installation into a fully-configured, beautiful, and modern web development system based on Hyprland by running a single command. That's the one-line pitch for Omarchy (like it was for Omakub). No need to write bespoke configs for every essential tool just to get started or to be up on all the latest command-line tools. Omarchy is an opinionated take on what Linux can be at its best.

Read more at [omarchy.org](https://omarchy.org).

## Installation

To install Omarchy, run the following command in your terminal:

```bash
# With this ENV username and this ENV email, run bash that will execute a curl command to download the boot.sh script, and pipe the contents of that script to bash for execution
OMARCHY_USER_NAME="your_username" OMARCHY_USER_EMAIL="your_email@example.com" bash -c 'curl -fsSL https://raw.githubusercontent.com/RATIU5/omarchy/refs/heads/master/boot.sh | bash'
```

## Differences

My configuration of Omarchy has some differences. These include:

### Packages

| Package Name                  | Status  |
| ----------------------------- | ------- |
| helix                         | Added   |
| tailscale                     | Added   |
| zsh-completions               | Added   |
| zen-browser-bin               | Added   |
| alacritty                     | Removed |
| bash-completions              | Removed |
| fcitx5, fcitx5-gtk, fcitx5-qt | Removed |
| kdenlive                      | Removed |
| libreoffice                   | Removed |
| luarocks                      | Removed |
| mariadb-libs                  | Removed |
| nvim                          | Removed |
| obs-studio                    | Removed |
| omarchy-chromium              | Removed |
| pinta                         | Removed |
| python-poetry-core            | Removed |
| python-terminaltexteffects    | Removed |
| signal-desktop                | Removed |
| spotify                       | Removed |
| xournalpp                     | Removed |

### Webapps

| Webapp Name     | Status  |
| --------------- | ------- |
| Slack           | Added   |
| Teams           | Added   |
| HEY             | Removed |
| Basecamp        | Removed |
| WhatsApp        | Removed |
| Google Photos   | Removed |
| Google Contacts | Removed |
| Google Messages | Removed |
| ChatGPT         | Removed |
| YouTube         | Removed |
| GitHub          | Removed |
| X               | Removed |

## License

Omarchy is released under the [MIT License](https://opensource.org/licenses/MIT).
