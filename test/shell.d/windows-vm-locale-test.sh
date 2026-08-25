#!/bin/bash
#
# omarchy-windows-vm install follows the host locale into dockur LANGUAGE /
# REGION / KEYBOARD. These cases fake localectl, LANG, and vconsole XKBLAYOUT
# and assert the compose yaml — they do not need KVM or gum.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
export OMARCHY_WINDOWS_DIR="$TMPDIR/win"
export OMARCHY_VCONSOLE="$TMPDIR/missing-vconsole"

set -- help
source "$ROOT/bin/omarchy-windows-vm" >/dev/null 2>&1
COMPOSE="$OMARCHY_WINDOWS_DIR/docker-compose.yml"

# In production the write elevates via pkexec; here run it in-process.
priv() { local a=$1; shift; "__priv_$a" "$@"; }

compose_from_host() {
  rm -f "$COMPOSE"
  write_compose 4G 2 64G alice pw UTC /home/alice/.windows /home/alice/Windows
}

locale_env() {
  grep -E '^[[:space:]]*(LANGUAGE|REGION|KEYBOARD):' "$COMPOSE"
}

# Issue #7901: LANG stays en_US while localectl reports a German keyboard.
localectl() {
  cat <<'EOF'
   System Locale: LANG=en_US.UTF-8
       VC Keymap: de
      X11 Layout: de
EOF
}
export LANG=en_US.UTF-8
compose_from_host
grep -q 'LANGUAGE: "de"' "$COMPOSE" || fail "de keyboard sets LANGUAGE=de" "$(locale_env)"
grep -q 'REGION: "de-DE"' "$COMPOSE" || fail "de keyboard sets REGION=de-DE" "$(locale_env)"
grep -q 'KEYBOARD: "de-DE"' "$COMPOSE" || fail "de keyboard sets KEYBOARD=de-DE" "$(locale_env)"
grep -q 'TZ: "UTC"' "$COMPOSE" || fail "TZ is still written alongside locale"
pass "German localectl layout maps to de / de-DE / de-DE"

localectl() {
  cat <<'EOF'
   System Locale: LANG=en_US.UTF-8
       VC Keymap: us
      X11 Layout: us
EOF
}
export LANG=en_US.UTF-8
compose_from_host
grep -q 'LANGUAGE: "en"' "$COMPOSE" || fail "English host sets LANGUAGE=en" "$(locale_env)"
grep -q 'REGION: "en-US"' "$COMPOSE" || fail "English host sets REGION=en-US" "$(locale_env)"
grep -q 'KEYBOARD: "en-US"' "$COMPOSE" || fail "English host sets KEYBOARD=en-US" "$(locale_env)"
[[ $(grep -c '^[[:space:]]*LANGUAGE:' "$COMPOSE" || true) == 1 ]] || fail "English compose duplicated LANGUAGE"
pass "English host maps to en / en-US"

localectl() { return 1; }
export LANG=de_DE.UTF-8
compose_from_host
grep -q 'LANGUAGE: "de"' "$COMPOSE" || fail "LANG=de_DE sets LANGUAGE=de" "$(locale_env)"
grep -q 'REGION: "de-DE"' "$COMPOSE" || fail "LANG=de_DE sets REGION=de-DE" "$(locale_env)"
grep -q 'KEYBOARD: "de-DE"' "$COMPOSE" || fail "LANG=de_DE sets KEYBOARD=de-DE" "$(locale_env)"
pass "LANG=de_DE.UTF-8 maps to de / de-DE without localectl"

localectl() { return 1; }
export LANG=C
printf 'XKBLAYOUT=de\n' >"$TMPDIR/vconsole.conf"
export OMARCHY_VCONSOLE="$TMPDIR/vconsole.conf"
compose_from_host
grep -q 'LANGUAGE: "de"' "$COMPOSE" || fail "vconsole XKBLAYOUT=de sets LANGUAGE=de" "$(locale_env)"
grep -q 'REGION: "de-DE"' "$COMPOSE" || fail "vconsole XKBLAYOUT=de sets REGION=de-DE" "$(locale_env)"
grep -q 'KEYBOARD: "de-DE"' "$COMPOSE" || fail "vconsole XKBLAYOUT=de sets KEYBOARD=de-DE" "$(locale_env)"
pass "vconsole XKBLAYOUT=de maps to de / de-DE"
export OMARCHY_VCONSOLE="$TMPDIR/missing-vconsole"

localectl() {
  cat <<'EOF'
   System Locale: LANG=de_DE.UTF-8
       VC Keymap: de
      X11 Layout: de
EOF
}
export LANG=de_DE.UTF-8
compose_from_host
write_compose 4G 2 64G alice pw UTC /home/alice/.windows /home/alice/Windows
[[ $(grep -c '^[[:space:]]*LANGUAGE:' "$COMPOSE" || true) == 1 ]] || fail "re-install duplicated LANGUAGE"
[[ $(grep -c '^[[:space:]]*REGION:' "$COMPOSE" || true) == 1 ]] || fail "re-install duplicated REGION"
[[ $(grep -c '^[[:space:]]*KEYBOARD:' "$COMPOSE" || true) == 1 ]] || fail "re-install duplicated KEYBOARD"
pass "re-install writes LANGUAGE/REGION/KEYBOARD once"

rm -f "$COMPOSE"
printf 'RAM=%s\nCORES=%s\nDISK=%s\nUSERNAME=%s\nPASSWORD=%s\nTZ=%s\nSTORAGE=%s\nSHARED=%s\nLANGUAGE=%s\n' \
  4G 2 64G alice pw UTC /a /b 'de; rm -rf /' | __priv_write_compose
grep -q 'LANGUAGE: "en"' "$COMPOSE" || fail "invalid LANGUAGE should fall back to en"
grep -q 'de; rm' "$COMPOSE" && fail "invalid LANGUAGE must not be copied into the compose"
pass "invalid LANGUAGE falls back to en instead of being copied"
