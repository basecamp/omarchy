#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

migration="$ROOT/migrations/1787864608.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

stub_bin="$test_dir/bin"
pam="$test_dir/pam_env.conf"
migration_copy="$test_dir/migration.sh"
mkdir -p "$stub_bin"

legacy="PATH DEFAULT=/usr/local/sbin:/usr/local/bin:/usr/bin:@{HOME}/.local/share/mise/shims:@{HOME}/.local/bin"
updated="PATH DEFAULT=/usr/local/sbin:/usr/local/bin:/usr/bin:@{HOME}/.local/share/mise/shims:@{HOME}/.local/bin:@{HOME}/.cargo/bin"
custom="PATH DEFAULT=/usr/bin:@{HOME}/custom/bin"

occurrences=$(grep -Fo '/etc/security/pam_env.conf' "$migration" | wc -l) || occurrences=0
(( occurrences == 1 )) ||
  fail "the migration names pam_env.conf exactly once, so the test can retarget a copy" \
    "found $occurrences occurrences"
grep -Fxq 'pam="/etc/security/pam_env.conf"' "$migration" ||
  fail "the production pam path is a fixed literal, not caller-controlled"
pass "migration names pam_env.conf once, and the test drives a retargeted copy"

sed "s#/etc/security/pam_env.conf#$pam#g" "$migration" >"$migration_copy"

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB
chmod +x "$stub_bin/sudo"

run_migration() {
  PATH="$stub_bin:$PATH" bash -euo pipefail "$migration_copy" >/dev/null
}

# Legacy Omarchy line: rewritten to include cargo.
printf '%s\n' "# Omarchy: give SSH commands and other non-shell logins the user-level tool paths" "$legacy" >"$pam"
run_migration || fail "migration runs against the legacy Omarchy PAM PATH"
grep -qxF -- "$updated" "$pam" || fail "migration rewrites the legacy line to include cargo" "actual: $(cat "$pam")"
grep -qxF -- "$legacy" "$pam" && fail "migration must remove the legacy line"
pass "migration upgrades the exact Omarchy-managed legacy PATH line"

# Already current: no-op and still succeeds.
before=$(cat "$pam")
run_migration || fail "migration is idempotent when cargo is already present"
[[ $(cat "$pam") == "$before" ]] || fail "migration must not rewrite an already-current PAM PATH"
pass "migration is a no-op when the PAM PATH already includes cargo"

# Custom PATH: leave alone.
printf '%s\n' "$custom" >"$pam"
run_migration || fail "migration runs when PATH is custom"
grep -qxF -- "$custom" "$pam" || fail "migration must preserve a custom PAM PATH"
grep -q 'cargo/bin' "$pam" && fail "migration must not append cargo onto a custom PAM PATH"
pass "migration leaves custom PAM PATH configuration alone"

# Missing file: no-op.
rm -f "$pam"
run_migration || fail "migration tolerates a missing pam_env.conf"
[[ ! -e $pam ]] || fail "migration must not create pam_env.conf when it was missing"
pass "migration no-ops when pam_env.conf is missing"
