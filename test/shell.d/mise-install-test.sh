#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

home="$test_dir/home"
bin_dir="$home/.local/bin"
stub_bin="$test_dir/bin"
installs="$test_dir/mise-installs"
mise_log="$test_dir/mise-log"
argv0_bin="$test_dir/argv0printer"
argv0_is_bash=0
mkdir -p "$stub_bin" "$installs"

# A native binary is the only way to observe argv[0]: a shebang script loses
# the forged name before line 1, which is the wrapper bug this installer fixes.
if command -v cc >/dev/null; then
  cc -o "$argv0_bin" -x c - <<'EOF'
#include <stdio.h>

int main(int argc, char **argv) {
  if (argc > 0) {
    puts(argv[0]);
  }
  return 0;
}
EOF
else
  ln -sf "$(command -v bash)" "$argv0_bin"
  argv0_is_bash=1
fi

cat >"$stub_bin/mise" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$MISE_LOG"

if [[ $1 == "use" ]]; then
  if (( ${MISE_USE_FAIL:-0} )); then
    exit 1
  fi
  exit 0
fi

if [[ $1 == "where" ]]; then
  if (( ${MISE_WHERE_FAIL:-0} )); then
    exit 1
  fi
  printf '%s\n' "$MISE_WHERE"
  exit 0
fi

exit 0
SH
chmod +x "$stub_bin/mise"

seed_tool() {
  local package=$1
  local bin=$2
  local root="$installs/$package"

  mkdir -p "$root"
  cp "$argv0_bin" "$root/$bin"
  chmod +x "$root/$bin"
}

invoke_argv0() {
  local dest=$1
  local name=$2

  if (( argv0_is_bash )); then
    bash -c 'exec -a "$1" "$2" -c "printf %s\\n \"\$BASH_ARGV0\""' _ "$name" "$dest"
  else
    bash -c 'exec -a "$1" "$2"' _ "$name" "$dest"
  fi
}

run_install() {
  HOME="$home" PATH="$stub_bin:$ROOT/bin:$PATH" \
    MISE_LOG="$mise_log" MISE_WHERE="$MISE_WHERE" \
    MISE_USE_FAIL="${MISE_USE_FAIL:-0}" MISE_WHERE_FAIL="${MISE_WHERE_FAIL:-0}" \
    "$ROOT/bin/omarchy-mise-install" "$@"
}

: >"$mise_log"
seed_tool claude claude
MISE_WHERE="$installs/claude"
run_install claude

dest="$bin_dir/claude"
[[ -L $dest ]] || fail "installer creates a symlink, not a script"
[[ $(readlink "$dest") == "$installs/claude/claude" ]] ||
  fail "symlink points at the real binary"
pass "installer creates a symlink to the real binary"

got=$(invoke_argv0 "$dest" ugrep)
[[ $got == "ugrep" ]] || fail "symlink preserves argv[0] via exec -a" "expected ugrep, got: $got"
pass "symlink preserves argv[0] via exec -a"

grep -qx 'use -g --quiet claude' "$mise_log" || fail "installer still calls mise use -g --quiet"
grep -qx 'where claude' "$mise_log" || fail "installer resolves the binary with mise where"
if awk '$1 == "x" { found = 1 } END { exit found ? 0 : 1 }' "$mise_log"; then
  fail "installer no longer re-execs through mise x"
fi
pass "installer still calls mise use -g --quiet"

# Missing target: where points at a tree that has no executable bin.
: >"$mise_log"
mkdir -p "$installs/missing"
MISE_WHERE="$installs/missing"
if run_install missing >/dev/null 2>&1; then
  fail "missing target exits non-zero"
fi
pass "missing target exits non-zero"

# Unusable target: the file exists but is not executable.
: >"$mise_log"
mkdir -p "$installs/unusable"
printf '#!/bin/bash\nexit 0\n' >"$installs/unusable/unusable"
chmod a-x "$installs/unusable/unusable"
MISE_WHERE="$installs/unusable"
if run_install unusable >/dev/null 2>&1; then
  fail "unusable target exits non-zero"
fi
pass "unusable target exits non-zero"

: >"$mise_log"
MISE_WHERE="$installs/claude"
MISE_USE_FAIL=1
if run_install claude >/dev/null 2>&1; then
  fail "mise use failure exits non-zero"
fi
pass "mise use failure exits non-zero"

: >"$mise_log"
MISE_USE_FAIL=0
MISE_WHERE_FAIL=1
if run_install claude >/dev/null 2>&1; then
  fail "mise where failure exits non-zero"
fi
pass "mise where failure exits non-zero"

# Replacing an old wrapper file with a symlink.
MISE_WHERE_FAIL=0
mkdir -p "$bin_dir"
rm -f "$bin_dir/claude"
cat >"$bin_dir/claude" <<'EOF'
#!/bin/bash
export MISE_MINIMUM_RELEASE_AGE=0
mise use -g --quiet "claude" || exit 1
exec mise x "claude" -- "claude" "$@"
EOF
chmod +x "$bin_dir/claude"
[[ -L $bin_dir/claude ]] && fail "precondition: old wrapper is a regular file"

: >"$mise_log"
MISE_WHERE="$installs/claude"
run_install claude

[[ -L $bin_dir/claude ]] || fail "installer replaces an old wrapper with a symlink"
[[ $(readlink "$bin_dir/claude") == "$installs/claude/claude" ]] ||
  fail "replacement symlink points at the real binary"
got=$(invoke_argv0 "$bin_dir/claude" ugrep)
[[ $got == "ugrep" ]] || fail "replacement symlink preserves argv[0]" "expected ugrep, got: $got"
pass "installer replaces an old wrapper with a symlink"

# command-name and bin-name can differ from the package.
seed_tool "github:can1357/oh-my-pi" omp
: >"$mise_log"
MISE_WHERE="$installs/github:can1357/oh-my-pi"
run_install "github:can1357/oh-my-pi" omp

[[ -L $bin_dir/omp ]] || fail "custom command name is a symlink"
[[ $(readlink "$bin_dir/omp") == "$installs/github:can1357/oh-my-pi/omp" ]] ||
  fail "custom command name points at the package bin"
grep -qx 'use -g --quiet github:can1357/oh-my-pi' "$mise_log" ||
  fail "custom package still uses mise use -g --quiet"
pass "command-name can differ from the package"

if HOME="$home" "$ROOT/bin/omarchy-mise-install" >/dev/null 2>&1; then
  fail "missing package argument exits non-zero"
fi
pass "missing package argument exits non-zero"
