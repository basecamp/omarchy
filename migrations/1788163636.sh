echo "Replace unauthenticated Apple T2 packages with signed Omarchy packages"

pacman_conf=/etc/pacman.conf
repair_marker=/var/lib/omarchy/t2-package-provenance-repaired
t2_packages=(linux-t2 linux-t2-headers apple-t2-audio-config apple-bcm-firmware t2fanrd)

disable_unsafe_t2_repository() (
  [[ -f $pacman_conf ]] || return 0
  local section backup

  section=$(/usr/bin/awk '
    found && /^[[:space:]]*\[/ { exit }
    /^[[:space:]]*\[arch-mact2\][[:space:]]*$/ { found = 1 }
    found { print }
  ' "$pacman_conf")
  [[ -n $section ]] || return 0
  /usr/bin/grep -Eq '^[[:space:]]*SigLevel[[:space:]]*=.*((Package)?(Never|Optional)|TrustAll)([[:space:]]|$)' <<<"$section" || return 0

  backup="$(/usr/bin/dirname "$pacman_conf")/arch-mact2.omarchy-disabled.$(/usr/bin/date +%s).txt"
  sudo /usr/bin/install -T -o root -g root -m 0600 /dev/stdin "$backup" <<<"$section"
  /usr/bin/awk '
    /^[[:space:]]*\[arch-mact2\][[:space:]]*$/ { drop = 1; next }
    drop && /^[[:space:]]*\[/ { drop = 0 }
    !drop { print }
  ' "$pacman_conf" |
    sudo /usr/bin/install -T -o root -g root -m 0644 /dev/stdin "$pacman_conf"
  echo "Disabled the unsafe arch-mact2 section; preserved it at $backup"
)

# This is intentionally first. If package discovery, download, signature
# validation, or reinstall fails later, retrying is safe and the unsigned
# repository remains unavailable.
disable_unsafe_t2_repository

[[ ! -e $repair_marker ]] || exit 0

has_t2_hardware=0
if /usr/bin/lspci -nn | /usr/bin/grep "106b:180[12]" >/dev/null; then
  has_t2_hardware=1
fi
has_t2_packages=0
for package in "${t2_packages[@]}"; do
  if /usr/bin/pacman -Q "$package" >/dev/null 2>&1; then
    has_t2_packages=1
    break
  fi
done
((has_t2_hardware || has_t2_packages)) || exit 0

# Do not assume an earlier update helper ran this migration. Ask pacman for the
# effective policy and require both mandatory package signatures and trusted
# signers before querying or reinstalling any replacement.
effective_siglevel=$(/usr/bin/pacman-conf --config "$pacman_conf" --repo omarchy SigLevel 2>/dev/null) || {
  echo "Could not resolve the Omarchy repository signature policy; refusing T2 replacement." >&2
  exit 1
}
if [[ -z ${effective_siglevel//[$' \t\n\r']/} ]]; then
  effective_siglevel=$(/usr/bin/pacman-conf --config "$pacman_conf" SigLevel 2>/dev/null) || {
    echo "Could not resolve the inherited package signature policy; refusing T2 replacement." >&2
    exit 1
  }
fi
effective_siglevel=${effective_siglevel//$'\n'/ }
effective_siglevel=${effective_siglevel//$'\t'/ }
if [[ " $effective_siglevel " != *" PackageRequired "* ||
  " $effective_siglevel " != *" PackageTrustedOnly "* ||
  " $effective_siglevel " == *" PackageOptional "* ||
  " $effective_siglevel " == *" PackageNever "* ||
  " $effective_siglevel " == *" PackageTrustAll "* ]]; then
  echo "The Omarchy repository does not enforce trusted package signatures; refusing T2 replacement." >&2
  exit 1
fi

# Resolve every replacement before beginning the reinstall, and require the
# pinned-key Omarchy repository by name. The repository itself inherits the
# effective package-required/trusted-only policy verified above.
for package in "${t2_packages[@]}"; do
  repository=$(LC_ALL=C /usr/bin/pacman -Si "$package" 2>/dev/null |
    /usr/bin/awk -F: '/^Repository[[:space:]]*:/ { gsub(/[[:space:]]/, "", $2); print $2; exit }')
  if [[ $repository != "omarchy" ]]; then
    echo "Authenticated replacement '$package' is unavailable from the Omarchy repository." >&2
    echo "The unsafe repository is disabled. Publish all signed T2 artifacts, then retry this migration." >&2
    exit 1
  fi
done

# No --needed: the bytes already installed under SigLevel=Never have no trusted
# provenance even when their version equals the signed replacement.
if ! sudo /usr/bin/pacman -S --noconfirm "${t2_packages[@]}"; then
  echo "Authenticated T2 package reinstall failed; leaving the repair pending." >&2
  exit 1
fi

marker_dir=$(/usr/bin/dirname "$repair_marker")
sudo /usr/bin/install -d -o root -g root -m 0755 "$marker_dir"
printf 'Reinstalled from signed Omarchy repository at %s\n' "$(/usr/bin/date --iso-8601=seconds)" |
  sudo /usr/bin/install -T -o root -g root -m 0644 /dev/stdin "$repair_marker"
