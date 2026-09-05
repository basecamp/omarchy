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
# Only the exact stack those commands produced is touched. Every non-blank,
# non-comment line must be one of the known hardware-auth auth lines (the
# clamshell gate, pam_fprintd, or the FIDO2 pam_u2f line) or a bare
# `X required pam_unix.so`; all four bare pam_unix lines must be present; and
# system-auth must not already be included. This matches the fingerprint, FIDO2,
# combined, and post-removal (markerless, both remove commands strip only their
# own marker lines) layouts, and refuses any administrator-authored stack that
# carries other directives. The repair replaces only the bare pam_unix lines, so
# comments and the hardware-auth lines are preserved verbatim.

is_omarchy_vulnerable_stack() {
  local file=$1 line
  local re_gate='^auth[[:space:]]+\[success=1 default=ignore\][[:space:]]+pam_exec\.so quiet /usr/bin/omarchy-hw-laptop-closed[[:space:]]*$'
  local re_fprintd='^auth[[:space:]]+sufficient[[:space:]]+pam_fprintd\.so[[:space:]]*$'
  local re_u2f='^auth[[:space:]]+sufficient[[:space:]]+pam_u2f\.so cue authfile=/etc/fido2/fido2[[:space:]]*$'
  local re_bare='^(auth|account|password|session)[[:space:]]+required[[:space:]]+pam_unix\.so[[:space:]]*$'
  local phase

  # Already fixed, or partially converted: leave it alone (also makes reruns no-op).
  if grep -qE '(auth|account|password|session)[[:space:]]+include[[:space:]]+system-auth' "$file"; then
    return 1
  fi

  # The vulnerable signature: all four phases delegated to a bare pam_unix.
  for phase in auth account password session; do
    grep -qE "^${phase}[[:space:]]+required[[:space:]]+pam_unix\.so[[:space:]]*\$" "$file" || return 1
  done

  # Every meaningful line must be one Omarchy itself wrote; anything else means
  # an administrator has edited this file, so it is not ours to rewrite.
  while IFS= read -r line || [[ -n $line ]]; do
    [[ -z ${line//[[:space:]]/} ]] && continue
    [[ $line == \#* ]] && continue
    [[ $line =~ $re_gate || $line =~ $re_fprintd || $line =~ $re_u2f || $line =~ $re_bare ]] && continue
    return 1
  done <"$file"

  return 0
}

if [[ -f $polkit ]] && is_omarchy_vulnerable_stack "$polkit"; then
  echo "Rewriting $polkit to defer to system-auth (restores pam_faillock lockout)..."

  backup="$polkit.omarchy-bak.$(date +%s)"
  if ! sudo cp -a "$polkit" "$backup"; then
    echo "Could not back up $polkit; leaving it unchanged so the migration retries." >&2
    exit 1
  fi

  # Replace only the bare pam_unix lines; keep comments, blank lines, and the
  # hardware-auth (gate / pam_fprintd / pam_u2f) lines exactly as they are.
  rebuilt=$(sed -E 's/^(auth|account|password|session)([[:space:]]+)required[[:space:]]+pam_unix\.so[[:space:]]*$/\1\2include system-auth/' "$polkit")

  if ! printf '%s\n' "$rebuilt" | sudo tee "$polkit" >/dev/null; then
    echo "Could not write $polkit; restoring the original." >&2
    sudo cp -a "$backup" "$polkit" || true
    exit 1
  fi

  if grep -qE '^auth[[:space:]]+include[[:space:]]+system-auth' "$polkit"; then
    echo "Restored polkit brute-force protection. Previous file saved at $backup."
  else
    echo "polkit repair could not be verified; restoring the original file." >&2
    sudo cp -a "$backup" "$polkit"
    exit 1
  fi
fi
