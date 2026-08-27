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

# Source the command's functions; the dispatcher just prints usage for "help".
set -- help
source "$ROOT/bin/omarchy-windows-vm" >/dev/null 2>&1
COMPOSE="$OMARCHY_WINDOWS_DIR/docker-compose.yml"

write() { # RAM CORES DISK USER PASS TZ STORAGE SHARED
  printf 'RAM=%s\nCORES=%s\nDISK=%s\nUSERNAME=%s\nPASSWORD=%s\nTZ=%s\nSTORAGE=%s\nSHARED=%s\n' \
    "$@" | __priv_write_compose
}

# --- valid compose, with the dangerous bits pinned and unreachable by input ---
rm -f "$COMPOSE"
write 4G 2 64G alice 's3cret' Europe/Copenhagen /home/alice/.windows /home/alice/Windows
[[ -f $COMPOSE ]] || fail "writer produced a compose file"
grep -q 'image: dockurr/windows' "$COMPOSE" || fail "image is pinned"
grep -q -- '- NET_ADMIN' "$COMPOSE" || fail "cap_add is pinned"
grep -q -- '- /home/alice/.windows:/storage' "$COMPOSE" || fail "storage volume uses the given path"
grep -q -- '- /:/' "$COMPOSE" && fail "compose must never contain a host-root bind mount"
pass "writer emits a pinned compose with no host-root mount"

# --- injection attempts are rejected, no file written ---
rm -f "$COMPOSE"
write 4G 2 64G 'x -v /:/h' p UTC /a /b 2>/dev/null && fail "malicious username was accepted"
[[ ! -f $COMPOSE ]] || fail "no compose written for a bad username"
write 4G 2 64G ok p UTC '/a -v /etc:/etc' /b 2>/dev/null && fail "malicious storage path was accepted"
write '4G; rm -rf /' 2 64G ok p UTC /a /b 2>/dev/null && fail "malicious RAM was accepted"
pass "injection attempts in username, path, and RAM are rejected"

# --- password survives YAML (" \) and compose interpolation ($) ---
rm -f "$COMPOSE"
tricky='p@$$w:rd$HOME"x\y'
write 8G 4 64G bob "$tricky" UTC /h/.windows /h/Windows
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
export HOME="$TMPDIR/home"
mkdir -p "$HOME/.config/windows"
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
grep -q -- "- $HOME/.windows:/storage" "$COMPOSE_FILE" || fail "migration uses the user's home for the data volume"
grep -q -- '- /:/' "$COMPOSE_FILE" && fail "migration must not carry a host-root bind mount from a tampered legacy file"
grep -q -- '- /etc:/shared' "$COMPOSE_FILE" && fail "migration must not carry a tampered legacy volume path"
[[ ! -f $LEGACY_COMPOSE_FILE ]] || fail "migration removes the legacy compose"
pass "migration reconstructs data paths from \$HOME and ignores tampered legacy volumes"

# --- bring-up refuses a symlinked mount source (a symlink redirects the
#     privileged bind mount the same way traversal would; the string check on
#     the stored path cannot see it) ---
rm -f "$COMPOSE"
mkdir -p "$TMPDIR/realstore" "$TMPDIR/realshare"
write 4G 2 64G dave pw UTC "$TMPDIR/realstore" "$TMPDIR/realshare"
assert_mounts_safe || fail "real directory mount sources are accepted"
ln -sfn / "$TMPDIR/evilshare"
write 4G 2 64G dave pw UTC "$TMPDIR/realstore" "$TMPDIR/evilshare"
assert_mounts_safe && fail "a symlinked mount source must be refused"
pass "bring-up refuses a symlinked mount source"

# --- valid_path rejects traversal and non-normalized paths ---
for p in /home/u/.windows /var/lib/omarchy/windows; do
  valid_path "$p" || fail "valid_path rejected a normal path: $p"
done
for p in / /./ // /tmp/../etc /home/u/. '/home/u/../root' '/a//b'; do
  valid_path "$p" && fail "valid_path accepted a traversal/non-normalized path: $p"
done
pass "valid_path accepts normalized paths and rejects traversal"

# --- credentials are stored privately and round-trip (incl. = in password) ---
export CREDENTIALS_FILE="$TMPDIR/creds"
write_credentials 'carol' 'p=a$$w"x'
[[ $(stat -c '%a' "$CREDENTIALS_FILE") == "600" ]] || fail "credentials file is 0600"
[[ $(read_credential USERNAME) == "carol" ]] || fail "username round-trips"
[[ $(read_credential PASSWORD) == 'p=a$$w"x' ]] || fail "password (with =) round-trips"
pass "credentials are written 0600 and round-trip"
