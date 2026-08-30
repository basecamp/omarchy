echo "Disable SSH password authentication on existing key-based setups"

config=/etc/ssh/sshd_config.d/10-omarchy-hardening.conf
authorized_keys="$HOME/.ssh/authorized_keys"

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
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

if [[ ! -f $authorized_keys || -L $authorized_keys || ! -s $authorized_keys || ! -r $authorized_keys ]] ||
  ! ssh-keygen -lf "$authorized_keys" >/dev/null 2>&1; then
  echo "Leaving SSH password authentication unchanged because $authorized_keys has no usable public key."
  exit 0
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

# Syntax alone is insufficient because sshd uses the first value it reads. If
# another administrator rule wins, remove our ineffective file and keep the
# migration pending rather than claiming the machine is protected.
if ! as_root sshd -t; then
  as_root rm -f -- "$config" || true
  echo "sshd rejected the hardening config. Fix the SSH configuration and run omarchy-migrate again." >&2
  exit 1
fi

effective_config=$(as_root sshd -T) || {
  as_root rm -f -- "$config" || true
  echo "Could not inspect sshd's effective configuration. Run omarchy-migrate again after fixing SSH." >&2
  exit 1
}

if ! grep -qixF "passwordauthentication no" <<<"$effective_config" ||
  ! grep -qixF "kbdinteractiveauthentication no" <<<"$effective_config"; then
  as_root rm -f -- "$config" || true
  echo "Another SSH rule keeps password authentication enabled. Fix its ordering and run omarchy-migrate again." >&2
  exit 1
fi

# An enabled but deliberately stopped daemon picks the file up on its next
# start. Reload only a daemon that is currently serving connections so existing
# sessions survive while new ones get the hardened policy.
if systemctl is-active --quiet sshd.service 2>/dev/null; then
  if ! as_root systemctl reload sshd.service; then
    echo "The hardening config is valid but sshd could not reload it. Run omarchy-migrate again after fixing the service." >&2
    exit 1
  fi
fi
