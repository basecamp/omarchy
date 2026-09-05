#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_path="$test_tmp/bin"
mkdir -p "$mock_path"

cat >"$mock_path/pacman" <<'EOF'
#!/bin/bash
case "$1" in
  -Q)
    case "$2" in
      group-package-1)
        [[ -f $TEST_TMP/group-installed || -f $TEST_TMP/group-package-1-installed ]]
        ;;
      group-package-2)
        [[ -f $TEST_TMP/group-installed && -z ${INCOMPLETE_GROUP:-} ]]
        ;;
      regular-package)
        exit 0
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  -Sgq)
    if [[ $2 != example-group && $2 != incomplete-group ]]; then
      exit 1
    fi
    printf '%s\n' group-package-1 group-package-2
    ;;
  -S)
    printf '%s\n' "$*" >"$TEST_TMP/install-command"
    if [[ -n ${INCOMPLETE_GROUP:-} ]]; then
      touch "$TEST_TMP/group-package-1-installed"
    else
      touch "$TEST_TMP/group-installed"
    fi
    ;;
  *)
    exit 1
    ;;
esac
EOF

cat >"$mock_path/omarchy-pkg-missing" <<'EOF'
#!/bin/bash
exec "$ROOT/bin/omarchy-pkg-missing" "$@"
EOF

cat >"$mock_path/sudo" <<'EOF'
#!/bin/bash
if [[ $1 != pacman ]]; then
  exit 1
fi
shift
exec pacman "$@"
EOF

chmod +x "$mock_path/pacman" "$mock_path/omarchy-pkg-missing" "$mock_path/sudo"

PATH="$mock_path:$ROOT/bin:$PATH" TEST_TMP="$test_tmp" \
  "$ROOT/bin/omarchy-pkg-add" example-group

[[ $(<"$test_tmp/install-command") == "-S --noconfirm --needed example-group" ]] ||
  fail "package group is passed to pacman for installation"
pass "pkg add accepts a group whose member packages are installed"

rm -f "$test_tmp/install-command"
PATH="$mock_path:$ROOT/bin:$PATH" "$ROOT/bin/omarchy-pkg-add" regular-package

[[ ! -e "$test_tmp/install-command" ]] ||
  fail "pkg add does not reinstall an already-installed package"
pass "pkg add does not reinstall an already-installed package"

rm -f "$test_tmp/group-installed" "$test_tmp/group-package-1-installed"
if INCOMPLETE_GROUP=1 PATH="$mock_path:$ROOT/bin:$PATH" TEST_TMP="$test_tmp" \
  "$ROOT/bin/omarchy-pkg-add" incomplete-group; then
  fail "pkg add reports a group with a missing member"
fi
pass "pkg add reports a group with a missing member"
