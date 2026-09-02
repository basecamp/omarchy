echo "Restore polkit brute-force protection on machines that enabled fingerprint or FIDO2 auth"

polkit=/etc/pam.d/polkit-1

# When fingerprint or FIDO2 auth was set up while /etc/pam.d/polkit-1 did not yet
# exist -- the normal case on Arch, where the polkit package ships its stack in
# /usr/lib/pam.d/polkit-1 -- the setup commands hand-rolled an /etc/pam.d/polkit-1
# that lists pam_unix directly instead of `include system-auth`. That override
# dropped pam_faillock, so polkit prompts had no brute-force lockout and their
# failures never counted toward the shared tally. The setup commands now defer to
# system-auth; this repairs the files the old ones already wrote.
#
# In scope only when the file exists, no package owns it (Omarchy wrote it), it
# does not already defer to system-auth, and it carries an Omarchy hardware-auth
# marker (the clamshell gate, pam_fprintd, or the FIDO2 authfile). That pins the
# repair to the exact stack the setup commands produced and leaves an
# administrator's own polkit-1 untouched. Idempotent by construction: once
# system-auth is included, this run and every other user's run no-op.
if [[ -f $polkit ]] &&
  ! pacman -Qo "$polkit" &>/dev/null &&
  ! grep -qE '^auth[[:space:]]+include[[:space:]]+system-auth' "$polkit" &&
  grep -qE 'omarchy-hw-laptop-closed|pam_fprintd\.so|authfile=/etc/fido2/fido2' "$polkit"; then

  echo "Rewriting $polkit to defer to system-auth (restores pam_faillock lockout)..."

  # Keep the configured hardware-auth auth lines verbatim (the clamshell gate and
  # the pam_fprintd / pam_u2f 'sufficient' lines); only the bare pam_unix stack is
  # replaced with the system-auth includes the vendor file and the sudo stack use.
  hw_auth=$(grep -E '^auth' "$polkit" | grep -vE 'pam_unix\.so')

  rebuilt=$(
    [[ -n $hw_auth ]] && printf '%s\n' "$hw_auth"
    printf 'auth      include system-auth\n'
    printf 'account   include system-auth\n'
    printf 'password  include system-auth\n'
    printf 'session   include system-auth\n'
  )

  backup="$polkit.omarchy-bak.$(date +%s)"
  if sudo cp -a "$polkit" "$backup"; then
    printf '%s\n' "$rebuilt" | sudo tee "$polkit" >/dev/null

    if grep -qE '^auth[[:space:]]+include[[:space:]]+system-auth' "$polkit"; then
      echo "Restored polkit brute-force protection. Previous file saved at $backup."
    else
      echo "polkit repair could not be verified; restoring the original file." >&2
      sudo cp -a "$backup" "$polkit"
    fi
  else
    echo "Administrator privileges are required to repair $polkit. Run omarchy-migrate again from a terminal." >&2
  fi
fi
