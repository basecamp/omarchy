#!/bin/bash
#
# The Windows VM compose file is written by an elevated, input-validated writer
# into a root-owned directory. These tests pin the security-critical behavior:
# no input can inject a host-root bind mount or a privileged flag, the password
# survives both the YAML and the compose-interpolation layer, only known
# privileged actions dispatch, and legacy configs migrate without redownloading.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
export OMARCHY_WINDOWS_DIR="$TMPDIR/win"
export HOME="$TMPDIR/home"
mkdir -p "$HOME"

# Source the command's functions; the dispatcher just prints usage for "help".
set -- help
source "$ROOT/bin/omarchy-windows-vm" >/dev/null 2>&1
COMPOSE="$OMARCHY_WINDOWS_DIR/docker-compose.yml"

write() { # RAM CORES DISK USER PASS TZ
  printf 'RAM=%s\nCORES=%s\nDISK=%s\nUSERNAME=%s\nPASSWORD=%s\nTZ=%s\n' \
    "$@" | __priv_write_compose
}

# --- valid compose, with the dangerous bits pinned and unreachable by input ---
rm -f "$COMPOSE"
write 4G 2 64G alice 's3cret' Europe/Copenhagen
resolve_caller
[[ -f $COMPOSE ]] || fail "writer produced a compose file"
grep -q 'image: dockurr/windows' "$COMPOSE" || fail "image is pinned"
grep -q -- '- NET_ADMIN' "$COMPOSE" || fail "cap_add is pinned"
grep -q -- "- $EXPECTED_STORAGE:/storage" "$COMPOSE" || fail "storage uses the per-uid protected anchor"
grep -q -- "- $EXPECTED_SHARED:/shared" "$COMPOSE" || fail "shared files use the per-uid protected anchor"
[[ -L $HOME/.windows && $(realpath "$HOME/.windows") == "$EXPECTED_STORAGE" ]] || fail "home storage link targets the protected anchor"
[[ -L $HOME/Windows && $(realpath "$HOME/Windows") == "$EXPECTED_SHARED" ]] || fail "home shared link targets the protected anchor"
grep -q -- '- /:/' "$COMPOSE" && fail "compose must never contain a host-root bind mount"
pass "writer derives protected per-uid anchors and emits no host-root mount"

# --- injection attempts are rejected, no file written ---
rm -f "$COMPOSE"
write 4G 2 64G 'x -v /:/h' p UTC 2>/dev/null && fail "malicious username was accepted"
[[ ! -f $COMPOSE ]] || fail "no compose written for a bad username"
printf 'RAM=4G\nCORES=2\nDISK=64G\nUSERNAME=ok\nPASSWORD=p\nTZ=UTC\nSTORAGE=/\nSHARED=/etc\n' | __priv_write_compose
grep -q -- "- $EXPECTED_STORAGE:/storage" "$COMPOSE" || fail "caller-supplied storage path affected the compose"
grep -q -- '- /:/storage' "$COMPOSE" && fail "host root was accepted as storage"
write '4G; rm -rf /' 2 64G ok p UTC 2>/dev/null && fail "malicious RAM was accepted"
pass "injection attempts are rejected and caller-supplied paths are ignored"

# --- password survives YAML (" \) and compose interpolation ($) ---
rm -f "$COMPOSE"
tricky='p@$$w:rd$HOME"x\y'
write 8G 4 64G bob "$tricky" UTC
grep -q 'PASSWORD: ".*\$\$.*"' "$COMPOSE" || fail "\$ is escaped as \$\$ for compose interpolation"
recovered=$(unescape "$(read_compose_value PASSWORD "$COMPOSE")")
[[ $recovered == "$tricky" ]] || fail "password round-trips through write/unescape"
pass "password with \" \\ and \$ round-trips"

# --- only known privileged actions may dispatch ---
for action in write_compose up up_wait down status remove; do
  valid_priv_action "$action" || fail "known privileged action rejected: $action"
done
for action in '/../evil/x' bogus 'up;rm' '' '__priv_up'; do
  valid_priv_action "$action" && fail "privileged action whitelist accepted: [$action]"
done
pass "privileged action whitelist accepts known actions and rejects the rest"

# --- legacy per-user compose migrates into the root-owned location ---
# A rogue process could have rewritten the user-owned legacy compose to bind
# mount host / into the guest, so migration must ignore its volume paths and
# reconstruct them from the current user's $HOME.
rm -rf "$OMARCHY_WINDOWS_DIR"
rm -rf "$MOUNT_ROOT"
rm -f "$HOME/.windows" "$HOME/Windows"
mkdir -p "$HOME/.config/windows" "$HOME/.windows" "$HOME/Windows"
touch "$HOME/.windows/existing-disk" "$HOME/Windows/existing-shared-file"
LEGACY_COMPOSE_FILE="$HOME/.config/windows/docker-compose.yml"
COMPOSE_FILE="$COMPOSE"
cat >"$LEGACY_COMPOSE_FILE" <<'LEG'
services:
  windows:
    environment:
      RAM_SIZE: "16G"
      CPU_CORES: "6"
      DISK_SIZE: "128G"
      USERNAME: "legacyuser"
      PASSWORD: "legacypass"
      TZ: "America/New_York"
    volumes:
      - /./:/storage
      - /etc:/shared
LEG
# In production the write elevates via pkexec; here run it in-process.
priv() { local a=$1; shift; "__priv_$a" "$@"; }
migrate_legacy_compose
[[ -f $COMPOSE_FILE ]] || fail "migration wrote the root-owned compose"
grep -q 'USERNAME: "legacyuser"' "$COMPOSE_FILE" || fail "migration preserves settings"
resolve_caller
grep -q -- "- $EXPECTED_STORAGE:/storage" "$COMPOSE_FILE" || fail "migration uses the protected storage anchor"
grep -q -- "- $EXPECTED_SHARED:/shared" "$COMPOSE_FILE" || fail "migration uses the protected shared anchor"
[[ -f $EXPECTED_STORAGE/existing-disk ]] || fail "migration preserves the existing disk data"
[[ -f $EXPECTED_SHARED/existing-shared-file ]] || fail "migration preserves existing shared files"
[[ -L $HOME/.windows && -L $HOME/Windows ]] || fail "migration replaces home entries with compatibility links"
grep -q -- '- /:/' "$COMPOSE_FILE" && fail "migration must not carry a host-root bind mount from a tampered legacy file"
grep -q -- '- /etc:/shared' "$COMPOSE_FILE" && fail "migration must not carry a tampered legacy volume path"
[[ ! -f $LEGACY_COMPOSE_FILE ]] || fail "migration removes the legacy compose"
pass "legacy migration pins existing data and ignores tampered legacy volumes"

# --- bring-up accepts only the derived pair in a trusted compose ---
assert_mounts_safe || fail "real directory mount sources are accepted"
sed -i "s|$EXPECTED_SHARED:/shared|/etc:/shared|" "$COMPOSE"
assert_mounts_safe 2>/dev/null && fail "a tampered host path must be refused"
sed -i "s|/etc:/shared|$EXPECTED_SHARED:/shared|" "$COMPOSE"
chmod 0666 "$COMPOSE"
assert_mounts_safe 2>/dev/null && fail "a user-writable compose must be refused"
chmod 0640 "$COMPOSE"
pass "bring-up rejects unexpected mounts and a writable compose"

# --- a symlink supplied as legacy data is renamed below the protected parent
#     before inspection, then quarantined rather than followed ---
rm -rf "$OMARCHY_WINDOWS_DIR"
rm -rf "$MOUNT_ROOT"
rm -f "$HOME/.windows" "$HOME/Windows"
ln -s / "$HOME/.windows"
mkdir -p "$HOME/Windows"
rm -f "$COMPOSE"
write 4G 2 64G dave pw UTC 2>/dev/null && fail "a symlinked legacy data entry was accepted"
[[ ! -f $COMPOSE ]] || fail "no compose is written for a symlinked legacy entry"
[[ ! -L $MOUNT_ROOT/users/$(id -u)/storage ]] || fail "the mount anchor must not remain a symlink"
find "$MOUNT_ROOT/users/$(id -u)" -maxdepth 1 -type l -name 'rejected-storage-*' | grep -q . || fail "the rejected symlink was not quarantined"
pass "migration pins and rejects a symlinked legacy data entry"

# --- credentials are stored privately and round-trip (incl. = in password) ---
export CREDENTIALS_FILE="$TMPDIR/creds"
write_credentials 'carol' 'p=a$$w"x'
[[ $(stat -c '%a' "$CREDENTIALS_FILE") == "600" ]] || fail "credentials file is 0600"
[[ $(read_credential USERNAME) == "carol" ]] || fail "username round-trips"
[[ $(read_credential PASSWORD) == 'p=a$$w"x' ]] || fail "password (with =) round-trips"
pass "credentials are written 0600 and round-trip"
