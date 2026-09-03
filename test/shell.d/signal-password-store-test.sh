#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

export HOME="$tmp_dir/home"
mkdir -p "$HOME"

migration="$ROOT/migrations/1788562800.sh"
flags="$HOME/.config/signal-desktop-flags.conf"

# The migration pins the store on an existing install, without touching a
# user-chosen --password-store line.
bash "$migration"
grep -qx -- '--password-store=gnome-libsecret' "$flags" ||
  fail "the migration pins Signal to gnome-libsecret" "$(cat "$flags")"
lines_before=$(wc -l <"$flags")
bash "$migration"
(( $(wc -l <"$flags") == lines_before )) ||
  fail "the migration is idempotent" "$(cat "$flags")"
pass "existing installs get the Signal password-store pin once"

printf '%s\n' '--password-store=basic_text' >"$flags"
bash "$migration"
grep -qx -- '--password-store=basic_text' "$flags" ||
  fail "a user-chosen password-store line is respected" "$(cat "$flags")"
grep -q -- '--password-store=gnome-libsecret' "$flags" &&
  fail "the migration does not override a user choice" "$(cat "$flags")"
pass "an explicit password-store choice wins"
rm -f "$flags"

# The install path writes the same pin before the first launch, so a fresh
# install never starts with the fallback backend.
mkdir -p "$tmp_dir/bin"
cat >"$tmp_dir/bin/omarchy-pkg-add" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$PKG_ADD_LOG"
EOF
cat >"$tmp_dir/bin/uwsm-app" <<'EOF'
#!/bin/bash
:
EOF
cat >"$tmp_dir/bin/setsid" <<'EOF'
#!/bin/bash
"$@"
EOF
chmod +x "$tmp_dir/bin"/*
cat >"$tmp_dir/leaf.sh" <<EOF
#!/bin/bash
set -e
PATH="$tmp_dir/bin:\$PATH" PKG_ADD_LOG="$tmp_dir/pkg-add.log" bash "$ROOT/bin/omarchy-install-service-signal"
EOF
chmod +x "$tmp_dir/leaf.sh"
bash "$tmp_dir/leaf.sh" >/dev/null
grep -qx -- '--password-store=gnome-libsecret' "$flags" ||
  fail "the install path pins Signal before first launch" "$(cat "$flags" 2>/dev/null || echo missing)"
grep -qx 'signal-desktop' "$tmp_dir/pkg-add.log" ||
  fail "Signal is still installed" "$(cat "$tmp_dir/pkg-add.log")"
rm -f "$flags"
bash "$tmp_dir/leaf.sh" >/dev/null
(( $(grep -c -- '--password-store=' "$flags") == 1 )) ||
  fail "re-installing does not duplicate the pin" "$(cat "$flags")"
pass "the install path pins Signal once and stays idempotent"

pass "Signal is pinned to gnome-libsecret on both install and migration paths"
