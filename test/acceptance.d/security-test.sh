#!/bin/bash
#
# Verifies the security posture of an installed system: the unprivileged
# session-to-root paths closed for 4.0.2 (blanket input-group grant, shipped
# asdcontrol sudoers authorization) and the SSH hardening flow.
#
# The sshd section reconfigures the machine (enables sshd, opens the firewall,
# disables password logins), so it demands explicit opt-in: it only runs when
# OMARCHY_ACCEPTANCE_SUDO_PASSWORD is set, which omarchy-iso-test does for its
# throwaway VMs. A cached sudo timestamp alone never triggers it, so running
# the suite on a machine you care about cannot reconfigure sshd by accident.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Membership of `input` gives raw access to /dev/input/event*: any process
# running as the user could log keystrokes. Only the opt-in controller and
# ydotool features may grant it.
verify_input_group() {
  if id -nG | grep -qw input; then
    if pacman -Q xpadneo-dkms &>/dev/null || pacman -Q ydotool &>/dev/null; then
      pass "input group membership is backed by an opt-in feature"
    else
      fail "user is not in the input group" "no controller or ydotool support installed to justify it"
    fi
  else
    pass "user is not in the input group"
  fi
}

sudo_available() {
  if sudo -n true 2>/dev/null; then
    return 0
  fi

  if [[ -n ${OMARCHY_ACCEPTANCE_SUDO_PASSWORD:-} ]]; then
    printf '%s\n' "$OMARCHY_ACCEPTANCE_SUDO_PASSWORD" | sudo -S -v 2>/dev/null
    return $?
  fi

  return 1
}

verify_asdcontrol_sudoers() {
  # Omarchy used to ship a passwordless sudoers grant for asdcontrol; that
  # authorization now belongs to the package alone.
  if sudo -n test -e /etc/sudoers.d/omarchy-asdcontrol; then
    fail "no omarchy asdcontrol sudoers grant is shipped" "/etc/sudoers.d/omarchy-asdcontrol exists"
  fi
  pass "no omarchy asdcontrol sudoers grant is shipped"
}

verify_sshd_hardening() {
  local key_file=/tmp/omarchy-acceptance-sshd-key
  local effective_config

  rm -f "$key_file" "$key_file.pub"
  ssh-keygen -t ed25519 -N "" -q -C "omarchy-acceptance" -f "$key_file"

  # sudo keys its cached credential on the calling terminal and, absent one, on
  # the caller's parent process alone, so a timestamp validated in this shell
  # never reaches the setup command's own sudo calls when the suite runs
  # without a terminal (omarchy-iso-test drives it over ssh with no pty). Give
  # the exercise a pseudo-terminal and validate the password on it first, so
  # every sudo underneath shares that terminal's credential.
  if ! OMARCHY_ACCEPTANCE_SUDO_PASSWORD="$OMARCHY_ACCEPTANCE_SUDO_PASSWORD" \
    OMARCHY_ACCEPTANCE_SSHD_KEY="$(cat "$key_file.pub")" SHELL=/bin/bash \
    script -qec 'printf "%s\n" "$OMARCHY_ACCEPTANCE_SUDO_PASSWORD" | sudo -S -v 2>/dev/null &&
      omarchy-setup-security-sshd --key="$OMARCHY_ACCEPTANCE_SSHD_KEY"' /dev/null \
    </dev/null >"$ARTIFACTS/setup-security-sshd.log" 2>&1; then
    fail "omarchy-setup-security-sshd completes unattended" "$(tail -5 "$ARTIFACTS/setup-security-sshd.log")"
  fi
  pass "omarchy-setup-security-sshd completes unattended"

  systemctl is-active sshd.service >/dev/null || fail "sshd is running after setup"
  pass "sshd is running after setup"

  grep -qxF "$(cat "$key_file.pub")" "$HOME/.ssh/authorized_keys" || fail "the key is authorized"
  pass "the key is authorized"

  # The command verifies its own hardening before keeping it, but assert the
  # effective config independently: sshd honors the first value it reads, and
  # regressions here reopen password logins. Keywords match case-insensitively
  # because OpenSSH 9.x dumps them lowercase and 10.x in CamelCase.
  effective_config=$(sudo -n sshd -T) || fail "sshd reports its effective config"
  grep -qixF "passwordauthentication no" <<<"$effective_config" || fail "password authentication is off"
  pass "password authentication is off"
  grep -qixF "kbdinteractiveauthentication no" <<<"$effective_config" || fail "keyboard-interactive authentication is off"
  pass "keyboard-interactive authentication is off"

  if omarchy-cmd-present ufw; then
    sudo -n ufw status | grep -qE '^22/tcp\s+LIMIT' || fail "the SSH port is rate limited in the firewall"
    pass "the SSH port is rate limited in the firewall"
  fi

  # Leave the machine as found where cheap: the throwaway key stays useless
  # once removed, while the hardening itself is the state under test.
  sed -i "\#$(cat "$key_file.pub" | cut -d' ' -f2)#d" "$HOME/.ssh/authorized_keys"
  rm -f "$key_file" "$key_file.pub"
}

verify_input_group

if sudo_available; then
  verify_asdcontrol_sudoers
else
  pass "asdcontrol sudoers check skipped: sudo needs a password"
fi

if [[ -n ${OMARCHY_ACCEPTANCE_SUDO_PASSWORD:-} ]] && sudo_available; then
  verify_sshd_hardening
else
  pass "sshd hardening exercise skipped: set OMARCHY_ACCEPTANCE_SUDO_PASSWORD to run it"
fi
