echo "Recover fingerprint authentication after suspend"

# fprintd keeps its pre-sleep handle for the reader across a suspend, so every
# Claim after a resume fails and PAM silently falls back to the password prompt.
# Installs that already configured fingerprint authentication need the sleep
# hook that restarts the daemon on resume.
if [[ -f /etc/pam.d/omarchy-lock-fingerprint && ! -x /usr/lib/systemd/system-sleep/fprintd-reset ]]; then
  sudo install -D -o root -g root -m 755 \
    "$OMARCHY_PATH/default/systemd/system-sleep/fprintd-reset" \
    /usr/lib/systemd/system-sleep/fprintd-reset
fi
