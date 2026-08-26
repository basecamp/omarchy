echo "Point RC-channel machines at the rc package repo"

# The rc package channel used to be a version-string convention on top of the
# edge repo: pacman-rc.conf paired rc-mirror.omarchy.org with
# pkgs.omarchy.org/edge. RC is now a real channel — release candidates publish
# to pkgs.omarchy.org/rc, which stays in parity with stable between trains —
# and edge will eventually stop carrying the omarchy/omarchy-settings pair.
#
# A machine on the RC Arch mirror whose [omarchy] repo still points at edge is
# an RC tester on the old pairing. Flip just that server line; the sed matches
# only the exact old URL, so a customized or already-migrated pacman.conf is
# left alone and re-running is a no-op. Edge/dev machines (mirror.omarchy.org)
# and stable machines never match the guard.

grep -q "https://rc-mirror.omarchy.org/" /etc/pacman.d/mirrorlist || exit 0
grep -q "https://pkgs.omarchy.org/edge/" /etc/pacman.conf || exit 0

# Dev-package machines deliberately follow edge regardless of mirror.
if pacman -Q omarchy-dev >/dev/null 2>&1; then
  exit 0
fi

sudo sed -i 's|https://pkgs.omarchy.org/edge/|https://pkgs.omarchy.org/rc/|' /etc/pacman.conf
echo "  [omarchy] repo moved from the edge to the rc channel"
