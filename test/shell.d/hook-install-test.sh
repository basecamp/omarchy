#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

test_home="$test_tmp/home"
mkdir -p "$test_home"

install_hook() {
  HOME="$test_home" PATH="$ROOT/bin:$PATH" \
    bash "$ROOT/bin/omarchy-hook-install" "$@" >"$test_tmp/out" 2>&1 || return $?
}

run_hook() {
  HOME="$test_home" PATH="$ROOT/bin:$PATH" \
    bash "$ROOT/bin/omarchy-hook" "$@" >"$test_tmp/out" 2>&1 || return $?
}

source_hook="$test_tmp/my-hook.sh"
cat >"$source_hook" <<'SH'
#!/usr/bin/env bash
echo "hook executed: $1" >> "$HOOK_LOG"
SH
chmod +x "$source_hook"

installed_path="$test_home/.config/omarchy/hooks/post-boot.d/my-hook.sh"

# ---------------------------------------------------------------- default copy
install_hook post-boot "$source_hook" || fail "hook install succeeds with default copy"
[[ -f "$installed_path" ]] || fail "installed hook exists at target destination"
[[ ! -L "$installed_path" ]] || fail "default install copies rather than symlinks"
[[ -x "$installed_path" ]] || fail "installed hook is executable"
pass "omarchy hook install copies the file by default"

# ---------------------------------------------------------------- --symlink & -s
rm -f "$installed_path"

install_hook --symlink post-boot "$source_hook" || fail "hook install succeeds with --symlink"
[[ -L "$installed_path" ]] || fail "target is a symbolic link with --symlink"
[[ $(readlink -f "$installed_path") == $(readlink -f "$source_hook") ]] || \
  fail "symlink points to the canonical source file"
pass "omarchy hook install --symlink creates a valid symbolic link"

# Re-run with short flag -s (idempotency check)
install_hook -s post-boot "$source_hook" || fail "hook install -s succeeds and overwrites existing symlink"
[[ -L "$installed_path" ]] || fail "target remains a symbolic link with -s"
pass "omarchy hook install -s supports short flag and is idempotent"

# Verify edits to source reflect through symlink
printf '\necho "updated"\n' >> "$source_hook"
grep -Fq "updated" "$installed_path" || fail "modifications to source file reflect through symlink"
pass "symlinked hook dynamically reflects changes to source"

# ---------------------------------------------------------------- runner executes symlink
hook_log="$test_tmp/hook.log"
HOOK_LOG="$hook_log" run_hook post-boot || fail "omarchy-hook runner executes successfully"
grep -Fq "hook executed:" "$hook_log" || fail "omarchy-hook executed the symlinked hook script"
pass "omarchy-hook runner successfully executes symlinked hooks"

# ---------------------------------------------------------------- error handling
if install_hook post-boot "$test_tmp/does-not-exist.sh"; then
  fail "hook install rejects non-existent source file"
fi
pass "hook install rejects non-existent source file"

if install_hook --invalid-flag post-boot "$source_hook"; then
  fail "hook install rejects unknown options"
fi
pass "hook install rejects unknown options"

if install_hook post-boot; then
  fail "hook install rejects missing arguments"
fi
pass "hook install rejects missing arguments"
