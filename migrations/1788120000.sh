echo "Sync the GNOME keyring on future user password changes"

# A password changed through Update > Password > User used to run plain
# passwd, which never re-encrypts an existing encrypted login keyring, so
# the next cold boot could not decrypt it (SDDM reset the login bar; the
# journal showed "gkr-pam: couldn't unlock the login keyring").
# omarchy-user-password now appends the pam_gnome_keyring password line to
# /etc/pam.d/passwd before changing the password, so the keyring is
# re-encrypted as part of the change itself.

# That only helps future changes. A keyring that a past password change
# already orphaned stays broken, so tell the user how to fix it instead of
# leaving a silent trap.

if omarchy-cmd-missing gnome-keyring-daemon; then
  # gnome-keyring is part of the default install; without it there is no
  # keyring to sync and plain passwd is the correct path.
  exit 0
fi

if [[ -f $HOME/.local/share/keyrings/login.keyring ]]; then
  echo "An encrypted login keyring was found on this machine."
  echo "If SDDM rejects your password after a restart, open Update >"
  echo "Password > User once and change the password to re-sync it."
fi
