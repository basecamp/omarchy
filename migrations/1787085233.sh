echo "Take the FIDO2 authfile out of the user's hands"

# pamu2fcfg ran unprivileged and `sudo mv` kept its ownership, so the authfile
# PAM consults for sudo and polkit ended up owned by the account it
# authenticates. Nothing else produced that file, so a non-root owner is the
# whole tell.
authfile="${OMARCHY_FIDO2_AUTHFILE:-/etc/fido2/fido2}"

[[ -f $authfile && $(stat -c '%u' "$authfile") != 0 ]] || exit 0

# Rename a root-owned copy over the path rather than chowning in place: chown
# leaves a descriptor opened before the repair writable on the same inode, and
# PAM would keep reading that inode.
sudo install -o root -g root -m 644 "$authfile" "$authfile.new"
sudo mv -f "$authfile.new" "$authfile"
