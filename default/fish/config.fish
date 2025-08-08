if status is-interactive
    # Commands to run in interactive sessions can go here
end

# Set complete path
set PATH "./bin:$HOME/.local/bin:$HOME/.local/share/omarchy/bin:$PATH"

# Omarchy path
set OMARCHY_PATH "/home/$USER/.local/share/omarchy"

# Editor used by CLI
set EDITOR nvim
set SUDO_EDITOR "$EDITOR"
set BAT_THEME ansi

#kubernetes 
alias k kubectl
alias kx kubectl
alias kn kubens

# File system
alias ls 'eza -lh --group-directories-first --icons=auto'
alias lsa 'ls -a'
alias lt 'eza --tree --level=2 --long --icons --git'
alias lta 'lt -a'
alias ff "fzf --preview 'bat --style=numbers --color=always {}'"
#alias cd zd

function zd
    if test (count $argv) -eq 0
        cd ~
    else if test -d "$argv[1]"
        cd "$argv[1]"
    else
        z $argv
        if test $status -eq 0
            printf " \U000F17A9 "
            pwd
        else
            echo "Error: Directory not found"
        end
    end
end

function open
    xdg-open $argv >/dev/null 2>&1 &
end

# Directories
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# Tools
alias g='git'
alias d='docker'
alias r='rails'

function n
    if test (count $argv) -eq 0
        nvim .
    else
        nvim "$argv[1]"
    end
end

# Git
alias gcm='git commit -m'
alias gcam='git commit -a -m'
alias gcad='git commit -a --amend'

# Find packages without leaving the terminal
alias yayf="yay -Slq | fzf --multi --preview 'yay -Sii {1}' --preview-window=down:75% | xargs -ro yay -S"

# Compression
function compress
    tar -czf "$argv[1].tar.gz" "$argv[1]"
end

alias decompress "tar -xzf"

# Write iso file to sd card
#
function iso2sd
    if test (count $argv) -ne 2
        echo "Usage: iso2sd <input_file> <output_device>"
        echo "Example: iso2sd ~/Downloads/ubuntu-25.04-desktop-amd64.iso /dev/sda"
        echo -e "\nAvailable SD cards:"
        lsblk -d -o NAME | grep -E '^sd[a-z]' | awk '{print "/dev/"$1}'
    else
        sudo dd bs=4M status=progress oflag=sync if=$argv[1] of=$argv[2]
        sudo eject $argv[2]
    end
end

# Format an entire drive for a single partition using ext4
function format-drive
    if test (count $argv) -ne 2
        echo "Usage: format-drive <device> <name>"
        echo "Example: format-drive /dev/sda 'My Stuff'"
        echo -e "\nAvailable drives:"
        lsblk -d -o NAME -n | awk '{print "/dev/"$1}'
    else
        echo "WARNING: This will completely erase all data on $argv[1] and label it '$argv[2]'."
        read -p 'echo "Are you sure you want to continue? (y/N): "' confirm
        if string match -qr '^[Yy]$' $confirm
            sudo wipefs -a $argv[1]
            sudo dd if=/dev/zero of=$argv[1] bs=1M count=100 status=progress
            sudo parted -s $argv[1] mklabel gpt
            sudo parted -s $argv[1] mkpart primary ext4 1MiB 100%
            set partition (string match -r 'nvme' $argv[1] && echo {$argv[1]}p1 || echo {$argv[1]}1)
            sudo mkfs.ext4 -L $argv[2] $partition
            echo "Drive $argv[1] formatted and labeled '$argv[2]'."
        end
    end
end
