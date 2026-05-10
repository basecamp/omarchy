#!/bin/bash

abort() {
    echo -e "\e[31mOmarchy install requires: $1\e[0m"
    echo
    gum confirm "Proceed anyway on your own accord and without assistance?" || exit 1
}

warn() {
    echo -e "\e[33mWarning: $1\e[0m"
}

# Determine install mode
MODE="${OMARCHY_INSTALL_MODE:-fresh}"
echo "Install mode: $MODE"

# MODE-SPECIFIC GUARDS
if [[ "$MODE" == "fresh" ]]; then
    # Strict guards for fresh install (current behavior)
    if [[ ! -f /etc/arch-release ]]; then
        abort "Vanilla Arch"
    fi
    
    for marker in /etc/cachyos-release /etc/eos-release /etc/garuda-release /etc/manjaro-release; do
        if [[ -f $marker ]]; then
            abort "Vanilla Arch"
        fi
    done
    
    if (( EUID == 0 )); then
        abort "Running as root (not user)"
    fi
    
    if [[ $(uname -m) != "x86_64" ]]; then
        abort "x86_64 CPU"
    fi
    
    if bootctl status 2>/dev/null | grep -q 'Secure Boot: enabled'; then
        abort "Secure Boot disabled"
    fi
    
    if pacman -Qe gnome-shell &>/dev/null || pacman -Qe plasma-desktop &>/dev/null; then
        abort "Fresh + Vanilla Arch"
    fi
    
    command -v limine &>/dev/null || abort "Limine bootloader"
    
    [[ $(findmnt -n -o FSTYPE /) = "btrfs" ]] || abort "Btrfs root filesystem"
    
else
    # Relaxed guards for overlay/dualboot
    if [[ ! -f /etc/arch-release ]]; then
        warn "Not vanilla Arch - some features may not work"
    fi
    
    for marker in /etc/cachyos-release /etc/eos-release /etc/garuda-release /etc/manjaro-release; do
        if [[ -f $marker ]]; then
            warn "Arch derivative detected - some features may not work"
        fi
    done
    
    if (( EUID == 0 )); then
        abort "Running as root (not user)"
    fi
    
    if [[ $(uname -m) != "x86_64" ]]; then
        warn "Not x86_64 - some features may not work"
    fi
    
    if bootctl status 2>/dev/null | grep -q 'Secure Boot: enabled'; then
        warn "Secure Boot enabled - bootloader may fail"
    fi
    
    if pacman -Qe gnome-shell &>/dev/null || pacman -Qe plasma-desktop &>/dev/null; then
        warn "Gnome/KDE detected - may conflict with Omarchy DE"
    fi
    
    # Only check limine for dualboot
    if [[ "$MODE" == "dualboot" ]]; then
        command -v limine &>/dev/null || warn "Limine not installed - bootloader may fail"
    fi
    
    # Warn on filesystem
    [[ $(findmnt -n -o FSTYPE /) = "btrfs" ]] || warn "Not btrfs - snapshots won't work"
fi

# Check for existing Omarchy installation
if [[ -d "$HOME/.local/share/omarchy" ]] && [[ "$MODE" != "fresh" ]]; then
    echo "Existing Omarchy installation detected - running in update mode"
fi

echo "Guards: OK"