echo "Remove unparseable default keyring stubs so secrets survive login"

# install/user/default-keyring.sh used to hand-write Default_keyring.keyring as
# a plaintext ini stub. gnome-keyring 50.x cannot parse it: on every login the
# daemon logs "invalid or unrecognized format", abandons the path, and creates
# Default_keyring_N.keyring empty — Chrome/Docker secrets from the previous
# session are gone. Quarantine any remaining plaintext stubs and keep only a
# default pointer so the daemon can create a native keyring on next use.

keyring_dir="$HOME/.local/share/keyrings"
default_file="$keyring_dir/default"
stub="$keyring_dir/Default_keyring.keyring"
quarantine_dir="$keyring_dir/omarchy-invalid-stub-backup"

is_plaintext_stub() {
  local file="$1"

  [[ -f $file && ! -L $file ]] || return 1
  # Native gnome-keyring files are binary (GnomeKeyring header). The Omarchy
  # stub is small ASCII beginning with [keyring].
  head -c 8 "$file" 2>/dev/null | grep -q '^\[keyring' || return 1
  grep -q '^display-name=' "$file" 2>/dev/null || return 1
  return 0
}

mkdir -p "$keyring_dir"

moved=0
for candidate in "$stub" "$keyring_dir"/Default_keyring_*.keyring; do
  [[ -e $candidate || -L $candidate ]] || continue
  is_plaintext_stub "$candidate" || continue

  mkdir -p "$quarantine_dir"
  base=${candidate##*/}
  dest="$quarantine_dir/$base"
  suffix=0
  while [[ -e $dest || -L $dest ]]; do
    ((++suffix))
    dest="$quarantine_dir/$base.$suffix"
  done
  mv -- "$candidate" "$dest"
  echo "Quarantined unparseable keyring stub: $candidate -> $dest"
  moved=1
done

if [[ ! -f $default_file ]]; then
  printf 'Default_keyring\n' >"$default_file"
  chmod 644 "$default_file"
fi

chmod 700 "$keyring_dir" 2>/dev/null || true

if (( moved )); then
  echo "gnome-keyring will create a native default keyring on next login."
fi
