# Configure pacman after package installation completes. Offline target package
# installs use the live ISO's offline pacman.conf until this final restore.
case "$(uname -m)" in
  aarch64)
    # Omarchy's pacman.conf and mirrorlist describe an x86_64 Arch system:
    # [multilib] is 32-bit x86 libraries and no ARM mirror carries it, and the
    # mirrorlist points at Omarchy's mirror of Arch, which is x86_64 only.
    # Arch Linux ARM also lays its tree out as $arch/$repo rather than Arch's
    # $repo/os/$arch, so the mirrorlist cannot be reused with a different host.
    #
    # Derive the config from Omarchy's instead: drop [multilib], keep [omarchy]
    # (its $arch placeholder resolves correctly), add Arch Linux ARM's own
    # [alarm] and [aur] repositories, and leave the mirrorlist the distribution
    # installed. Skipping this step is not an option: the live ISO's pacman.conf
    # only knows the offline mirror, which does not exist on the installed system.
    awk '
      /^\[multilib\]$/ { skip = 1; next }
      /^\[/            { skip = 0 }
      skip             { next }
      { print }
    ' "$OMARCHY_PATH/default/pacman/pacman-${OMARCHY_MIRROR:-stable}.conf" >/etc/pacman.conf
    printf '\n[alarm]\nInclude = /etc/pacman.d/mirrorlist\n\n[aur]\nInclude = /etc/pacman.d/mirrorlist\n' >>/etc/pacman.conf
    ;;
  *)
    cp -f "$OMARCHY_PATH/default/pacman/pacman-${OMARCHY_MIRROR:-stable}.conf" /etc/pacman.conf
    cp -f "$OMARCHY_PATH/default/pacman/mirrorlist-${OMARCHY_MIRROR:-stable}" /etc/pacman.d/mirrorlist
    ;;
esac

# Wait for CUPS to own the file, the way omarchy-settings does, so pacman does
# not turn the override into a .pacnew during ISO package installation.
if [[ -f $OMARCHY_PATH/etc-overrides/cups-cups-files.conf && -f /etc/cups/cups-files.conf ]]; then
  install -m 0640 -o root -g cups "$OMARCHY_PATH/etc-overrides/cups-cups-files.conf" /etc/cups/cups-files.conf
  rm -f /etc/cups/cups-files.conf.pacnew
fi

source "$OMARCHY_INSTALL/hardware/pacman.sh"
