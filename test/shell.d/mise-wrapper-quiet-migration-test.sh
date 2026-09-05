#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

migration="$ROOT/migrations/1787573629.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

home="$test_dir/home"
bin_dir="$home/.local/bin"
stub_bin="$test_dir/bin"
installs="$test_dir/mise-installs"
mise_log="$test_dir/mise-log"
mkdir -p "$bin_dir" "$stub_bin" "$installs"

cat >"$stub_bin/mise" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$MISE_LOG"

if [[ $1 == "where" ]]; then
  printf '%s\n' "$MISE_INSTALLS/$2"
  exit 0
fi

exit 0
SH

# The migration uses GNU `stat -c%s`. Provide it so the real script can run
# here, not only on Linux.
cat >"$stub_bin/stat" <<'SH'
#!/bin/bash
if [[ $1 == "-c%s" ]]; then
  wc -c <"$2" | awk '{ print $1 }'
  exit 0
fi
if [[ $1 == "-c" && $2 == "%s" ]]; then
  wc -c <"$3" | awk '{ print $1 }'
  exit 0
fi
exec /usr/bin/stat "$@"
SH
chmod +x "$stub_bin/mise" "$stub_bin/stat"

seed_tool() {
  local package=$1
  local bin=$2
  local root="$installs/$package"

  mkdir -p "$root"
  printf '#!/bin/bash\nexit 0\n' >"$root/$bin"
  chmod +x "$root/$bin"
}

# The migration calls omarchy-mise-install to rewrite a wrapper, so the real
# one has to be reachable: this proves the template it writes today, not a
# copy of it that could drift.
run_migration() {
  HOME="$home" PATH="$stub_bin:$ROOT/bin:$PATH" \
    MISE_LOG="$mise_log" MISE_INSTALLS="$installs" \
    bash -euo pipefail "$migration" >/dev/null
}

assert_symlink() {
  local command=$1 package=$2 bin=$3
  local dest="$bin_dir/$command"
  local expected="$installs/$package/$bin"

  [[ -L $dest ]] || fail "$command is a symlink after migration"
  [[ $(readlink "$dest") == "$expected" ]] ||
    fail "$command points at $package's $bin"
}

write_stale_wrapper() {
  local command=$1 package=$2 bin=$3

  cat >"$bin_dir/$command" <<EOF
#!/bin/bash
export MISE_MINIMUM_RELEASE_AGE=0
mise use -g "$package" || exit 1
exec mise x "$package" -- "$bin" "\$@"
EOF
  chmod +x "$bin_dir/$command"
}

# The template before MISE_MINIMUM_RELEASE_AGE was added. A wrapper installed
# by hand for a custom tool can still be on this form.
write_pre_export_wrapper() {
  local command=$1 package=$2 bin=$3

  cat >"$bin_dir/$command" <<EOF
#!/bin/bash
mise use -g "$package" || exit 1
exec mise x "$package" -- "$bin" "\$@"
EOF
  chmod +x "$bin_dir/$command"
}

write_stale_wrapper claude claude claude
write_stale_wrapper omp github:can1357/oh-my-pi omp
write_stale_wrapper ghui npm:@kitlangton/ghui ghui
write_pre_export_wrapper custom-tool "github:someone/custom-tool" custom-tool

# The form omarchy-mise-install wrote when the earlier PATH-recursion migration
# ran, and the one before that. Neither carries `|| exit 1`.
cat >"$bin_dir/mise-exec-era" <<'EOF'
#!/bin/bash
mise use -g "npm:some/tool"
exec mise exec "npm:some/tool" -- "tool-bin" "$@"
EOF
cat >"$bin_dir/bare-exec-era" <<'EOF'
#!/bin/bash
mise use -g "aqua:some/other"
exec "other-bin" "$@"
EOF
chmod +x "$bin_dir/mise-exec-era" "$bin_dir/bare-exec-era"

seed_tool claude claude
seed_tool "github:can1357/oh-my-pi" omp
seed_tool "npm:@kitlangton/ghui" ghui
seed_tool "github:someone/custom-tool" custom-tool
seed_tool "npm:some/tool" tool-bin
seed_tool "aqua:some/other" other-bin

: >"$mise_log"
run_migration

assert_symlink claude claude claude
grep -qx 'use -g --quiet claude' "$mise_log" ||
  fail "migration still calls mise use -g --quiet"
pass "migration replaces a stale wrapper with a symlink"

assert_symlink omp "github:can1357/oh-my-pi" omp
assert_symlink ghui "npm:@kitlangton/ghui" ghui
pass "migration preserves package and bin names"

assert_symlink custom-tool "github:someone/custom-tool" custom-tool
pass "migration rewrites wrappers on the pre-export template"

assert_symlink mise-exec-era "npm:some/tool" tool-bin
assert_symlink bare-exec-era "aqua:some/other" other-bin
pass "migration rewrites every generated form that predates --quiet"

[[ -x $bin_dir/claude ]] || fail "migration leaves the rewritten symlink executable"
pass "migration leaves the rewritten symlink executable"

# Running twice must not touch an already-converted symlink.
before=$(readlink "$bin_dir/claude")
run_migration
[[ $(readlink "$bin_dir/claude") == "$before" ]] || fail "migration is idempotent"
pass "migration is idempotent"

# Anything the generator did not write is the user's own file.
cat >"$bin_dir/hand-written" <<'EOF'
#!/bin/bash
export MISE_MINIMUM_RELEASE_AGE=0
mise use -g "something" || exit 1
echo "and then something else entirely"
EOF
cat >"$bin_dir/mismatched" <<'EOF'
#!/bin/bash
export MISE_MINIMUM_RELEASE_AGE=0
mise use -g "one-package" || exit 1
exec mise x "another-package" -- "bin" "$@"
EOF
# A generated wrapper someone added a line to. Regenerating would drop that
# line, so the exact-match check has to leave the whole file alone.
cat >"$bin_dir/customized" <<'EOF'
#!/bin/bash
export MISE_MINIMUM_RELEASE_AGE=0
export SOME_TOKEN=abc123
mise use -g "customized" || exit 1
exec mise x "customized" -- "customized" "$@"
EOF
printf '#!/bin/bash\necho hi\n' >"$bin_dir/unrelated"
# uv and uvx land in ~/.local/bin from the Python dev env. A wrapper is a few
# short lines, so a real binary must be skipped on size, never read in whole.
head -c 5000000 /dev/urandom >"$bin_dir/uv"
chmod +x "$bin_dir/uv"
ln -s "$bin_dir/claude" "$bin_dir/linked"

hand_written_before=$(cat "$bin_dir/hand-written")
mismatched_before=$(cat "$bin_dir/mismatched")
unrelated_before=$(cat "$bin_dir/unrelated")
customized_before=$(cat "$bin_dir/customized")

run_migration

[[ $(cat "$bin_dir/hand-written") == "$hand_written_before" ]] ||
  fail "migration leaves a hand-written script that calls mise alone"
[[ $(cat "$bin_dir/mismatched") == "$mismatched_before" ]] ||
  fail "migration leaves a wrapper whose two lines disagree alone"
[[ $(cat "$bin_dir/unrelated") == "$unrelated_before" ]] ||
  fail "migration leaves an unrelated script alone"
[[ $(cat "$bin_dir/customized") == "$customized_before" ]] ||
  fail "migration leaves a generated wrapper a user has added a line to alone"
[[ -L $bin_dir/linked ]] || fail "migration leaves a symlink alone"
if command -v gstat >/dev/null; then
  uv_size=$(gstat -c%s "$bin_dir/uv")
elif stat -c%s "$bin_dir/uv" >/dev/null 2>&1; then
  uv_size=$(stat -c%s "$bin_dir/uv")
else
  uv_size=$(stat -f%z "$bin_dir/uv")
fi
(( uv_size == 5000000 )) || fail "migration leaves a native binary alone"
pass "migration only rewrites wrappers it recognizes"

# A machine with no ~/.local/bin at all must not fail the run.
empty_home="$test_dir/empty-home"
mkdir -p "$empty_home"
HOME="$empty_home" PATH="$stub_bin:$ROOT/bin:$PATH" \
  MISE_LOG="$mise_log" MISE_INSTALLS="$installs" \
  bash -euo pipefail "$migration" >/dev/null ||
  fail "migration succeeds when ~/.local/bin is missing"
pass "migration succeeds when ~/.local/bin is missing"
