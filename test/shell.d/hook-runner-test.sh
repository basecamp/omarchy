#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

home="$test_tmp/home"
hooks="$home/.config/omarchy/hooks"
mkdir -p "$hooks/theme-set.d"

run_hook() {
  HOME="$home" PATH="$ROOT/bin:$PATH" "$ROOT/bin/omarchy-hook" "$@"
}

# Executable Python hook must run via shebang, not bash (#9845).
cat >"$hooks/theme-set.d/py-hook.py" <<'PY'
#!/usr/bin/env python3
import sys
print(f"py:{sys.argv[1]}")
PY
chmod +x "$hooks/theme-set.d/py-hook.py"

out=$(run_hook theme-set demo 2>&1) || fail "executable python hook runs" "$out"
[[ $out == *'py:demo'* ]] || fail "python hook printed via shebang" "$out"
if [[ $out == *'import: command not found'* || $out == *'Hook failed'* ]]; then
  fail "python hook must not be parsed by bash" "$out"
fi
pass "executable python hook runs via shebang"

# Non-executable shell snippet still runs under bash.
cat >"$hooks/theme-set.d/shell-snippet.sh" <<'SH'
echo "sh:$1"
SH
chmod a-x "$hooks/theme-set.d/shell-snippet.sh"

out=$(run_hook theme-set demo 2>&1) || fail "non-executable shell hook runs" "$out"
[[ $out == *'sh:demo'* ]] || fail "bash fallback runs non-executable shell" "$out"
[[ $out == *'py:demo'* ]] || fail "python hook still runs alongside shell snippet" "$out"
pass "non-executable shell hook still runs under bash"

# Flat single-file hook path respects +x too.
cat >"$hooks/font-set" <<'PY'
#!/usr/bin/env python3
print("flat-py")
PY
chmod +x "$hooks/font-set"
out=$(run_hook font-set 2>&1) || fail "flat executable hook runs" "$out"
[[ $out == *'flat-py'* ]] || fail "flat python hook output" "$out"
pass "flat executable hook runs via shebang"

# Failing executable still reports failure without aborting the runner.
cat >"$hooks/theme-set.d/fail.py" <<'PY'
#!/usr/bin/env python3
import sys
sys.exit(2)
PY
chmod +x "$hooks/theme-set.d/fail.py"
out=$(run_hook theme-set demo 2>&1) || true
[[ $out == *'Hook failed:'*fail.py* ]] || fail "failed executable hook is reported" "$out"
[[ $out == *'py:demo'* ]] || fail "sibling hooks still run after a failure" "$out"
pass "failed executable hook is reported without stopping siblings"
