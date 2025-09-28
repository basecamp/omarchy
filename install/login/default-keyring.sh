OMARCHY_DESCRIPTION="GNOME Keyring Default Setup"

omarchy_install() {
  KEYRING_DIR="$HOME/.local/share/keyrings"
  KEYRING_FILE="$KEYRING_DIR/Default_keyring.keyring"
  DEFAULT_FILE="$KEYRING_DIR/default"

  mkdir -p "$KEYRING_DIR"

  cat << EOF > "$KEYRING_FILE"
[keyring]
display-name=Default keyring
ctime=$(date +%s)
mtime=0
lock-on-idle=false
lock-after=false
EOF

  cat << EOF > "$DEFAULT_FILE"
Default_keyring
EOF

  chmod 700 "$KEYRING_DIR"
  chmod 600 "$KEYRING_FILE"
  chmod 644 "$DEFAULT_FILE"
}

omarchy_verify() {
  local KEYRING_DIR="$HOME/.local/share/keyrings"

  [[ -d "$KEYRING_DIR" ]] || add_error "Keyring directory missing"
  if [[ -d "$KEYRING_DIR" ]]; then
    local dir_perms=$(stat -c %a "$KEYRING_DIR")
    [[ "$dir_perms" == "700" ]] || add_warning "Keyring directory has permissions $dir_perms (should be 700)"
  fi

  [[ -f "$KEYRING_DIR/Default_keyring.keyring" ]] || add_error "Default keyring file missing"
  if [[ -f "$KEYRING_DIR/Default_keyring.keyring" ]]; then
    local file_perms=$(stat -c %a "$KEYRING_DIR/Default_keyring.keyring")
    [[ "$file_perms" == "600" ]] || add_warning "Keyring file has permissions $file_perms (should be 600)"
  fi

  [[ -f "$KEYRING_DIR/default" ]] || add_error "Default keyring selection file missing"
  if [[ -f "$KEYRING_DIR/default" ]]; then
    grep -q "Default_keyring" "$KEYRING_DIR/default" || add_error "Default keyring not set as default"
  fi
}
