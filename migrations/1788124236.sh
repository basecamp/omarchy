echo "Disable SSH password authentication, or sshd itself when no key is authorized"

config=/etc/ssh/sshd_config.d/10-omarchy-hardening.conf
authorized_keys="$HOME/.ssh/authorized_keys"

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

# Passwords staying enabled is the state the machine has been living with, so a
# condition this migration cannot repair completes with a notice instead of
# failing and holding up every migration queued behind it. Only missing
# privileges stay pending below, because rerunning from a terminal fixes that.
skip() {
  echo "$1 SSH password authentication remains enabled; run omarchy-setup-security-sshd to harden manually."
  exit 0
}

# The fixed setup command writes this file itself. Its presence is also the
# machine-wide completion state, so migrations run by another account no-op.
if [[ -e $config || -L $config ]]; then
  exit 0
fi

# Earlier versions enabled sshd before importing the key, but did not leave a
# marker saying that Omarchy configured it. Limit the repair to a daemon that is
# enabled or currently exposed and a user who already has a usable authorized
# key. A machine that never set SSH up exits without prompting for privileges.
if ! systemctl is-enabled --quiet sshd.service 2>/dev/null &&
  ! systemctl is-active --quiet sshd.service 2>/dev/null; then
  exit 0
fi

# sshd reads authorized_keys one entry per line, while ssh-keygen -lf
# fingerprints whole files in formats sshd does not accept there — a private
# key copied in by mistake passes the file-level check even though sshd finds
# no usable entry in it. Ask sshd's question instead: does any single line
# parse as a public key?
has_usable_key() {
  local line
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line =~ ^[[:space:]]*(#|$) ]]; then
      continue
    fi
    if ssh-keygen -lf /dev/stdin <<<"$line" >/dev/null 2>&1; then
      return 0
    fi
  done <"$authorized_keys"
  return 1
}

# A file that exists but cannot be read leaves the key question unanswered; do
# not treat it as proof the machine is password-only. [[ -f ]] and the read
# both follow symlinks on purpose: a dotfiles-managed authorized_keys link with
# a working key must not count as keyless.
if [[ -f $authorized_keys && ! -r $authorized_keys ]]; then
  skip "Could not read $authorized_keys to check for a usable key."
fi

# The old setup command enabled sshd before importing a key, so an aborted run
# left a password-only server exposed. Without a usable key there is nothing to
# harden: close the hole Omarchy opened by disabling the server. Omarchy is a
# desktop distro, so the console remains; re-enabling password SSH afterwards
# is an intentional, informed choice the warning explains how to make.
if [[ ! -f $authorized_keys ]] || ! has_usable_key; then
  if ! as_root systemctl disable --now sshd.service; then
    echo "Administrator privileges are required to close the password-only SSH server. Run omarchy-migrate again from a terminal." >&2
    exit 1
  fi
  echo "No usable SSH key is authorized, so sshd only accepted password logins. The SSH server has been disabled: run omarchy-setup-security-sshd to set it up with key-based authentication, or re-enable sshd to accept password logins anyway."
  exit 0
fi

# Under StrictModes, sshd's default, a group- or world-writable home directory,
# ~/.ssh, or authorized_keys makes sshd ignore the key that just validated, and
# passwords would then be the only way in. Tighten the two paths the setup
# command owns, exactly as it does; the home directory is not ours to change.
home_mode=$(stat -c '%a' "$HOME" 2>/dev/null) || skip "Could not inspect the permissions on $HOME."
if (( 8#$home_mode & 8#022 )); then
  skip "$HOME is group- or world-writable, so sshd would ignore the authorized key."
fi
if ! chmod 700 "$HOME/.ssh" || ! chmod 600 "$authorized_keys"; then
  skip "Could not tighten the permissions on $authorized_keys."
fi

echo "Disabling SSH password authentication on the existing key-based SSH setup..."
if ! as_root install -Dm644 /dev/stdin "$config" <<'CONF'
# Written by Omarchy once an SSH key was already authorized.
# Delete this file and reload sshd to allow password logins again.
PasswordAuthentication no
KbdInteractiveAuthentication no
CONF
then
  echo "Administrator privileges are required to harden the existing SSH setup. Run omarchy-migrate again from a terminal." >&2
  exit 1
fi

# The drop-in itself is always valid, so a rejection means the configuration
# was already broken before it arrived — the administrator's to repair.
if ! as_root sshd -t; then
  as_root rm -f -- "$config" || true
  skip "sshd rejected its configuration."
fi

effective_config=$(as_root sshd -T) || {
  as_root rm -f -- "$config" || true
  skip "Could not inspect sshd's effective configuration."
}

# Syntax alone is insufficient because sshd uses the first value it reads. An
# sshd_config predating the packaged sshd_config.d Include never reads the
# drop-in at all, and an earlier administrator rule overrides it. Either way
# the file is ineffective: remove it rather than claiming the machine is
# protected.
if ! grep -qixF "passwordauthentication no" <<<"$effective_config" ||
  ! grep -qixF "kbdinteractiveauthentication no" <<<"$effective_config"; then
  as_root rm -f -- "$config" || true
  skip "sshd does not apply the hardening drop-in, so an earlier rule or a config without the sshd_config.d include wins."
fi

# An enabled but deliberately stopped daemon picks the file up on its next
# start. Reload only a daemon that is currently serving connections so existing
# sessions survive while new ones get the hardened policy.
if systemctl is-active --quiet sshd.service 2>/dev/null; then
  if ! as_root systemctl reload sshd.service; then
    echo "The hardening config is installed and valid, but sshd did not reload; it takes effect when sshd next restarts." >&2
    exit 0
  fi
fi
