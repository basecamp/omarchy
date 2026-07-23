(
  # Only invite when there's a reader to use and it isn't set up yet (the lock
  # PAM file is the last thing the setup writes on success).
  if omarchy-hw-fingerprint && [[ ! -f /etc/pam.d/omarchy-lock-fingerprint ]]; then
    if [[ -n $(omarchy-notification-send -u critical -g 󰈷 "Setup Fingerprint Reader" "Enable sudo and unlocking with your fingerprint." -a) ]]; then
      omarchy-launch-floating-terminal-with-presentation omarchy-setup-security-fingerprint
    fi
  fi
) >/dev/null 2>&1 &
