echo "Take ownership of the FIDO2 authfile so it cannot be rewritten without root"

authfile="/etc/fido2/fido2"

# Nothing to repair on any machine that never set FIDO2 up, which is almost all
# of them. Checked before any sudo so those machines never see a password
# prompt. -L as well as -e: a dangling symlink is invisible to -e.
if [[ ! -L $authfile && ! -e $authfile ]]; then
  exit 0
fi

# No Omarchy code path puts a symlink here, so one means the file was replaced.
# Reported, not repaired: chown follows symlinks and would take ownership of
# the target instead, and removing it would strip sudo and polkit from anyone
# whose only credential is the token.
if [[ -L $authfile ]]; then
  echo "  $authfile is a symlink, not a regular file."
  echo "  Leaving it alone. If you did not create it, remove it and re-run Setup > Security > Fido2."
  exit 0
fi

# A directory or a device here is no more ours to rewrite than a symlink is,
# and chmod 600 on a directory would only make it untraversable.
if [[ ! -f $authfile ]]; then
  echo "  $authfile is not a regular file."
  echo "  Leaving it alone. Remove it and re-run Setup > Security > Fido2."
  exit 0
fi

# Migration state is per-user, so every account re-runs this. The file's own
# ownership is the state check: the second account finds the repair already
# done and exits without escalating.
owner=$(stat -c %U "$authfile" 2>/dev/null) || owner=""
mode=$(stat -c %a "$authfile" 2>/dev/null) || mode=""
if [[ $owner == "root" && $mode == "600" ]]; then
  exit 0
fi

# Setup used to `mv` this in from /tmp, which carried the invoking user's
# ownership into /etc. pam_u2f reads it as root from setuid-root sudo and
# polkit-agent-helper-1, and accepts a root-owned authfile for any user, so
# taking ownership only widens who FIDO2 works for -- while stopping the
# registering user from rewriting their own PAM credential without root.
#
# Rename a fresh copy over the path rather than chowning in place. A descriptor
# opened while the file was still the user's own stays writable on that inode
# through any later chmod or chown, since permission is checked at open(2), and
# pam_u2f resolving the path would keep landing on it. Replacing the inode
# leaves that descriptor writing to a file nothing reads.
sudo install -T -m 600 -o root -g root "$authfile" "$authfile.new"
sudo mv -Tf "$authfile.new" "$authfile"
