# Copy and paste function
function cpy
    set -l destination (argv[-1])  # Last parameter as the destination
    set -l items (argv[1..-2])  # All parameters except the last one

    for item in $items
        if test -f "$item"
            echo -e ":: Copying a file"
            cp "$item" "$destination"
        else if test -d "$item"
            echo -e ":: Copying a directory"
            cp -r "$item" "$destination"
        end
    end
end

# Remove files and directories
function rmv
    for item in $argv
        if test -f "$item"
            echo -e ":: Removing a file"
            rm "$item"
        else if test -d "$item"
            echo -e ":: Removing a directory"
            rm -rf "$item"
        else
            echo -e "[ !! ] $item does not exist or is neither a regular file nor a directory"
        end
    end
end

# Disk and memory resources
function fn_resources
    switch $argv[1]
        case __disk
            set disk_total (df / -h | awk 'NR==2 {print $2}')
            set disk_used (df / -h | awk 'NR==2 {print $3}')
            set disk_free (df / -h | awk 'NR==2 {print $4}')
            echo -e "Total: $disk_total\nUsed: $disk_used\nFree: $disk_free"
        case __memory
            set mem_total (free -h | awk 'NR==2 {print $2}')
            set mem_used (free -h | awk 'NR==2 {print $3}')
            set mem_free (free -h | awk 'NR==2 {print $7}')
            echo -e "Total: $mem_total\nUsed: $mem_used\nFree: $mem_free"
    end
end

# Check for updates
function fn_check_updates
    if type -q pacman
        set aurhlpr (command -v yay || command -v paru)
        set aur ($aurhlpr -Qua | wc -l)
        set ofc (checkupdates | wc -l)
        set upd (math $ofc + $aur)
        echo -e "[ UPDATES ]\n:: You have $upd updates available.\n:: Main: $ofc\n:: Aur: $aur"
    else if type -q dnf
        set upd (dnf check-update -q | wc -l)
        echo -e "[ UPDATES ]\n:: You have $upd updates available"
    else if type -q zypper
        set upd (zypper lu --best-effort | grep -c 'v  |')
        echo -e "[ UPDATES ]\n:: You have $upd updates available"
    else if type -q apt
        set upd (apt list --upgradable 2> /dev/null | grep -c '\[upgradable from')
        echo -e "[ UPDATES ]\n:: You have $upd updates available"
    else
        echo -e "Unsupported package manager."
        return 1
    end
end

# Update packages
function fn_update
    if type -q pacman
        set aur (command -v yay || command -v paru)
        $aur -Syyu --noconfirm
    else if type -q dnf
        sudo dnf update -y && sudo dnf upgrade -y --refresh
    else if type -q zypper
        sudo zypper ref && sudo zypper up -y
    else if type -q apt
        sudo apt update -y && sudo apt upgrade -y
    else
        echo -e "Unsupported package manager."
        return 1
    end
end

# Install software
function fn_install
    if type -q pacman
        set aur (command -v yay || command -v paru)
        $aur -S --noconfirm $argv
    else if type -q dnf
        sudo dnf install -y $argv
    else if type -q zypper
        sudo zypper in -y $argv
    else if type -q apt
        sudo apt install -y $argv
    else
        echo -e "Unsupported package manager."
        return 1
    end
end

# Uninstall software
function fn_uninstall
    if type -q pacman
        set aur (command -v yay || command -v paru)
        $aur -Rns $argv
    else if type -q dnf
        sudo dnf remove $argv
    else if type -q zypper
        sudo zypper rm $argv
    else if type -q apt
        sudo apt remove $argv
    else
        echo -e "Unsupported package manager."
        return 1
    end
end


# Run a program detached
function runfree
    $argv > /dev/null 2>&1 & disown
end

# Copy file with progress bar
function cppy
    if type -q rsync
        rsync -ah --info=progress2 $argv
    else
        echo -e "rsync is not installed."
    end
end

# Create and change directory
function md
    mkdir -p $argv && cd $argv
end
