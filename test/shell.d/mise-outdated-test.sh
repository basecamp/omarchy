#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/mise" <<'SH'
#!/bin/bash
[[ $1 == "outdated" ]] || exit 1

case "${TEST_MISE_OUTDATED:-clean}" in
  clean)
    echo '{}'
    ;;
  stale)
    cat <<'JSON'
{"claude":{"current":"2.1.258","latest":"2.1.259"},"codex":{"current":"0.152.0","latest":"0.153.0"}}
JSON
    ;;
  fail)
    exit 1
    ;;
esac
SH
chmod +x "$stub_bin/mise"

run_checker() {
  PATH="$stub_bin:$ROOT/bin:$PATH" \
    TEST_MISE_OUTDATED="${1:-clean}" \
    "$ROOT/bin/omarchy-mise-outdated"
}

stdout="$test_tmp/stdout"
stderr="$test_tmp/stderr"

if run_checker clean >"$stdout" 2>"$stderr"; then
  status=0
else
  status=$?
fi
[[ $status -eq 1 ]] || fail "outdated checker exits non-zero when no mise tools are outdated"
[[ ! -s $stdout ]] || fail "outdated checker is quiet on stdout when up to date" "$(cat "$stdout")"
pass "outdated checker reports no output when mise tools are current"

if run_checker stale >"$stdout" 2>"$stderr"; then
  status=0
else
  status=$?
fi
[[ $status -eq 0 ]] || fail "outdated checker exits successfully when mise tools are outdated"
grep -Fx 'claude 2.1.258 -> 2.1.259' "$stdout" >/dev/null || fail "outdated checker reports the outdated claude version" "$(cat "$stdout")"
grep -Fx 'codex 0.152.0 -> 0.153.0' "$stdout" >/dev/null || fail "outdated checker reports the outdated codex version" "$(cat "$stdout")"
pass "outdated checker lists each outdated mise tool with its current and latest version"

if run_checker fail >"$stdout" 2>"$stderr"; then
  status=0
else
  status=$?
fi
[[ $status -eq 1 ]] || fail "outdated checker exits non-zero when mise outdated fails"
[[ ! -s $stdout ]] || fail "outdated checker stays quiet on stdout when mise outdated fails" "$(cat "$stdout")"
pass "outdated checker treats a failed mise outdated call as nothing to report"

# No stub_bin and no system dirs on PATH, so this proves the checker backs off
# cleanly rather than happening to find a real mise on the test machine.
if PATH="$ROOT/bin" "$ROOT/bin/omarchy-mise-outdated" >"$stdout" 2>"$stderr"; then
  status=0
else
  status=$?
fi
[[ $status -eq 1 ]] || fail "outdated checker exits non-zero when mise is not installed"
[[ ! -s $stdout ]] || fail "outdated checker stays quiet on stdout when mise is not installed" "$(cat "$stdout")"
pass "outdated checker ignores systems without mise installed"
