KEYRING_DIR="$HOME/.local/share/keyrings"
KEYRING_FILE="$KEYRING_DIR/Default_keyring.keyring"
DEFAULT_FILE="$KEYRING_DIR/default"

mkdir -p "$KEYRING_DIR"

if [[ ! -f $KEYRING_FILE ]]; then
  cat > "$KEYRING_FILE" <<EOF
[keyring]
display-name=Default keyring
ctime=$(date +%s)
mtime=0
lock-on-idle=false
lock-after=false
EOF
fi

if [[ ! -f $DEFAULT_FILE ]]; then
  cat > "$DEFAULT_FILE" <<EOF
Default_keyring
EOF
fi

chmod 700 "$KEYRING_DIR"
chmod 600 "$KEYRING_FILE"
chmod 644 "$DEFAULT_FILE"
