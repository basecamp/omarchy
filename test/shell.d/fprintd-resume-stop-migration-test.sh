#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1787689809.sh"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

mock_bin="$tmp_dir/bin"
mkdir -p "$mock_bin"
cat >"$mock_bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB
chmod +x "$mock_bin/sudo"

src="$tmp_dir/fprintd-resume-stop"
dst="$tmp_dir/system-sleep/fprintd-resume-stop"
lock_pam="$tmp_dir/omarchy-lock-fingerprint"
printf '#!/bin/bash\n' >"$src"
chmod +x "$src"

run_migration() {
  PATH="$mock_bin:$PATH" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_FPRINTD_RESUME_SRC="$src" \
    OMARCHY_FPRINTD_RESUME_DST="$dst" \
    OMARCHY_LOCK_FINGERPRINT_PAM="$lock_pam" \
    bash -euo pipefail "$migration" >/dev/null
}

: >"$lock_pam"
run_migration
[[ -x $dst ]] || fail "migration installs executable fingerprint recovery"
pass "migration installs executable fingerprint recovery"

printf 'locally changed\n' >>"$dst"
run_migration
grep -q 'locally changed' "$dst" || fail "migration preserves an existing hook"
pass "migration preserves an existing hook"

rm -f "$lock_pam" "$dst"
run_migration
[[ ! -e $dst ]] || fail "migration skips machines without fingerprint authentication"
pass "migration skips machines without fingerprint authentication"
