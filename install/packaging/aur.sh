#!/usr/bin/env bash
# Build AUR packages for inclusion in the ISO.
# Expected environment:
#  - OMARCHY_INSTALL (path to install/ directory)
#  - OMARCHY_INSTALL_LOG_FILE (optional)
# Reads: $OMARCHY_INSTALL/omarchy-aur.packages (one package name per line, comments with #)
# Output: $OMARCHY_INSTALL/iso-aur-pkgs containing built .pkg.* artifacts

set -euo pipefail

OM_INSTALL="${OMARCHY_INSTALL:-$HOME/.local/share/omarchy/install}"
AUR_LIST="$OM_INSTALL/omarchy-aur.packages"
OUTDIR="${OM_INSTALL}/iso-aur-pkgs"
TMPDIR="$(mktemp -d)"

mkdir -p "$OUTDIR"

if [[ ! -f "$AUR_LIST" ]]; then
  echo "No AUR package list found at $AUR_LIST — nothing to do."
  rm -rf "$TMPDIR"
  exit 0
fi

# Ensure build deps exist (base-devel, git). The ISO builder should have these available for builds.
sudo pacman -S --needed --noconfirm base-devel git || true

# Read package names (strip comments and blanks)
mapfile -t aur_packages < <(grep -v '^#' "$AUR_LIST" | grep -v '^$' || true)

if [[ ${#aur_packages[@]} -eq 0 ]]; then
  echo "No AUR packages listed in $AUR_LIST"
  rm -rf "$TMPDIR"
  exit 0
fi

pushd "$TMPDIR" >/dev/null

for pkg in "${aur_packages[@]}"; do
  echo "==> Processing AUR package: $pkg"

  # Clean any previous folder
  rm -rf "$pkg"
  # Try to fetch PKGBUILD via yay (preferred), fall back to git clone
  if command -v yay >/dev/null 2>&1; then
    if ! yay -G --noconfirm "$pkg" 2>/dev/null; then
      echo "yay -G failed for $pkg; trying git clone"
      git clone "https://aur.archlinux.org/${pkg}.git" "$pkg"
    fi
  else
    git clone "https://aur.archlinux.org/${pkg}.git" "$pkg"
  fi

  if [[ ! -d "$pkg" ]]; then
    echo "Failed to fetch PKGBUILD for $pkg; skipping."
    continue
  fi

  pushd "$pkg" >/dev/null

  # Build the package. These flags may need adjusting depending on the package (GPG, checks, etc).
  # The ISO-builder machine should be prepared to provide any required keys or to allow skipping GPG checks.
  if ! makepkg -s --noconfirm 2>/dev/null; then
    echo "makepkg failed for $pkg. Trying makepkg without --noconfirm."
    if ! makepkg -s; then
      echo "makepkg still failed for $pkg — skipping."
      popd >/dev/null
      continue
    fi
  fi

  # Copy built packages into output dir
  cp -v ./*.pkg.* "$OUTDIR"/ || echo "No package files produced for $pkg"

  popd >/dev/null
done

# Install the built packages
if compgen -G "$OUTDIR/*.pkg.tar.*" > /dev/null; then
  echo "==> Installing AUR packages into system"
  sudo pacman -U --noconfirm "$OUTDIR"/*.pkg.tar.*
else
  echo "No packages to install"
fi

# Cleanup
popd >/dev/null
rm -rf "$TMPDIR"
