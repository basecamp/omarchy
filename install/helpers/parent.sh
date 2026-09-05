# Shared by omarchy-parent and its feature commands (omarchy-parent-*), so a
# feature can install a sudoers grant the same careful way, and read and
# document its own keys in the parent's settings file, without copying the
# code. Sourced after the caller has defined `fail`.

SUDOERS_DIR="${OMARCHY_SUDOERS_DIR:-/etc/sudoers.d}"
PARENT_CONF="${OMARCHY_PARENT_CONF:-/etc/omarchy/parent.conf}"

# Stage in the target directory itself, so the final rename is atomic and a
# stray stage file, whose name carries a dot, is one sudo ignores. visudo
# checks the stage before it can become live: a sudoers file that fails to
# parse locks sudo out. Identical content is left alone.
install_sudoers() {
  local name="$1" content="$2"
  local target="$SUDOERS_DIR/$name" stage

  if [[ -f $target ]] && [[ $(<"$target") == "$content" ]]; then
    return 0
  fi

  install -d -m 755 "$SUDOERS_DIR"
  stage=$(mktemp "$SUDOERS_DIR/.$name.XXXXXX")
  printf '%s\n' "$content" >"$stage"
  if ! visudo -cf "$stage" >/dev/null; then
    rm -f "$stage"
    fail "generated sudoers file $name does not parse; nothing was changed"
  fi
  chmod 440 "$stage"
  mv -f "$stage" "$target"
}

# The parent's settings: one key=value per line, world-readable, with every
# key documented in place by whichever command owns it (conf_document), so a
# parent reading the file sees every choice and its default. A hand edit
# takes effect at the owning command's next apply. The file outlives
# `omarchy-parent apply --remove` and every feature's off on purpose.
conf_init() {
  [[ -f $PARENT_CONF ]] && return 0
  mkdir -p "$(dirname "$PARENT_CONF")"
  cat >"$PARENT_CONF" <<'CONF'
# Omarchy kids mode: what the kid account may do without the parent password,
# and what the parent has switched on. Each key is explained where it appears.
# Change a value and run the matching `sudo omarchy-parent` command's apply
# (`sudo omarchy-parent apply --user <kid>` for the keys omarchy-parent owns),
# or use that command directly; it edits this file for you.
CONF
  chmod 644 "$PARENT_CONF"
}

conf_get() {
  local key="$1" default="$2" value=""
  if [[ -f $PARENT_CONF ]]; then
    value=$(sed -n "s/^[[:space:]]*$key[[:space:]]*=[[:space:]]*//p" "$PARENT_CONF" | tail -1)
    value=${value%"${value##*[![:space:]]}"}
  fi
  printf '%s\n' "${value:-$default}"
}

conf_set() {
  local key="$1" value="$2" stage
  conf_init
  stage=$(mktemp)
  if grep -q "^[[:space:]]*$key[[:space:]]*=" "$PARENT_CONF"; then
    sed "s/^[[:space:]]*$key[[:space:]]*=.*/$key=$value/" "$PARENT_CONF" >"$stage"
  else
    { cat "$PARENT_CONF"; printf '%s=%s\n' "$key" "$value"; } >"$stage"
  fi
  install -m644 "$stage" "$PARENT_CONF"
  rm -f "$stage"
}

# conf_document KEY DEFAULT COMMENT... appends a commented block and the
# default the first time a command sees the file, and leaves a key the parent
# has already set alone.
conf_document() {
  local key="$1" default="$2" line
  shift 2
  conf_init
  grep -q "^[[:space:]]*$key[[:space:]]*=" "$PARENT_CONF" && return 0
  {
    echo
    for line in "$@"; do printf '# %s\n' "$line"; done
    printf '%s=%s\n' "$key" "$default"
  } >>"$PARENT_CONF"
}
