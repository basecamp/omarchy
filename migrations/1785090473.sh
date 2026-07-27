echo "Switch fingerprint support back to stock libfprint"

# libfprint-git existed to carry the focaltech_moc driver and the FocalTech
# FT9349 device ID (2808:a97a) before any release shipped them. libfprint
# 1.94.100 has both, so fingerprint setups go back to the stock Arch package.

# The remove/install pair below isn't one transaction: if the install failed
# on a previous run, libfprint-git is already gone but fprintd is left with
# no libfprint — the elif finishes the job on rerun.
if pacman -Q libfprint-git &>/dev/null; then
  # Deps-only removal keeps fprintd installed while its libfprint
  # dependency is swapped out underneath it.
  sudo pacman -Rdd --noconfirm libfprint-git
  omarchy-pkg-add libfprint
elif pacman -Q fprintd &>/dev/null && ! pacman -Q libfprint &>/dev/null; then
  omarchy-pkg-add libfprint
fi
