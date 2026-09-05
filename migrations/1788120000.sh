echo "Sync the GNOME keyring on future user password changes"

# A password changed through Update > Password > User used to run plain
# passwd, which never re-encrypts an existing encrypted login keyring, so
# the next cold boot could not decrypt it (SDDM reset the login bar; the
# journal showed "gkr-pam: couldn't unlock the login keyring").
# omarchy-user-password now appends the pam_gnome_keyring password line to
# /etc/pam.d/passwd before changing the password, so the keyring is
# re-encrypted as part of the change itself.

# This migration installs that same PAM line for installs that never run
# omarchy-user-password again, so a password changed through plain passwd
# on the terminal is re-encrypted too. Idempotent: once the line is in the
# stack, a later run (or another user on the same machine) skips the append.

if omarchy-cmd-missing gnome-keyring-daemon; then
  # gnome-keyring is part of the default install; without it there is no
  # keyring to sync and plain passwd is the correct path.
  exit 0
fi

PASSWD_PAM=/etc/pam.d/passwd

if ! grep -q '^password.*pam_gnome_keyring\.so' "$PASSWD_PAM"; then
  # Same line, same rationale as bin/omarchy-user-password (ArchWiki:
  # GNOME/Keyring). Runs as the user; the sudo prompt is the user saying
  # yes to the repair, which is what the update terminal is for.
  if ! echo 'password       optional       pam_gnome_keyring.so' | sudo tee -a "$PASSWD_PAM" >/dev/null; then
    # A migration that cannot finish must exit non-zero so it stays
    # pending and stops the queue rather than silently half-fixing.
    echo "Could not append the pam_gnome_keyring line to $PASSWD_PAM."
    echo "The keyring sync is not installed. The migration will retry on"
    echo "the next update once the sudo prompt is accepted."
    exit 1
  fi
  echo "Enabled GNOME keyring sync on password change."
fi

# Machines where a past password change already orphaned the keyring are
# NOT repaired by any of the above: pam_gnome_keyring unlocks the keyring
# with the keyring's own old password, so once the login password has moved
# on, another ordinary password change cannot re-sync it. Do not pretend
# otherwise; point at real recovery instead.

if [[ -f $HOME/.local/share/keyrings/login.keyring ]]; then
  echo "Your login keyring may still hold your OLD password (for example if a"
  echo "password was changed before this fix). If you are asked for a keyring"
  echo "password at login, or SDDM rejects a password you know is right,"
  echo "either:"
  echo "  - open 'Passwords and Keys' (seahorse), right-click the Login"
  echo "    keyring, 'Change Password', and set it back to your login"
  echo "    password, then change your login password once through"
  echo "    Update > Password > User; or"
  echo "  - delete the login keyring in 'Passwords and Keys' to start a"
  echo "    fresh one (saved Wi-Fi and browser passwords in it are lost)."
fi
