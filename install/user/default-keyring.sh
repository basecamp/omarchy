# Seed a passwordless default keyring pointer for gnome-keyring.
#
# Do not hand-write Default_keyring.keyring. Omarchy used to plant a plaintext
# ini-style stub there; gnome-keyring 50.x cannot parse that format, logs
# "invalid or unrecognized format", abandons the file, and creates a fresh
# empty Default_keyring_N.keyring on every login — wiping Chrome Safe Storage,
# Docker credentials, and every other secret stored in the previous session.
# Let the daemon create the keyring file natively on first use.
KEYRING_DIR="$HOME/.local/share/keyrings"
DEFAULT_FILE="$KEYRING_DIR/default"

mkdir -p "$KEYRING_DIR"

if [[ ! -f $DEFAULT_FILE ]]; then
  printf 'Default_keyring\n' >"$DEFAULT_FILE"
fi

chmod 700 "$KEYRING_DIR"
chmod 644 "$DEFAULT_FILE"
