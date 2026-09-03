#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

migration="$ROOT/migrations/1787573629.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

home="$test_dir/home"
bin_dir="$home/.local/bin"
mkdir -p "$bin_dir"

# The migration calls omarchy-mise-install to rewrite a wrapper, so the real
# one has to be reachable: this proves the template it writes today, not a
# copy of it that could drift.
run_migration() {
  HOME="$home" PATH="$ROOT/bin:$PATH" bash -euo pipefail "$migration" >/dev/null
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

run_migration

grep -qF 'mise use -g --quiet "claude" || exit 1' "$bin_dir/claude" ||
  fail "migration adds --quiet to a stale wrapper"
pass "migration adds --quiet to a stale wrapper"

grep -qF 'mise use -g --quiet "github:can1357/oh-my-pi" || exit 1' "$bin_dir/omp" ||
  fail "migration keeps a wrapper's package when the command name differs"
grep -qF 'exec mise x "github:can1357/oh-my-pi" -- "omp" "$@"' "$bin_dir/omp" ||
  fail "migration keeps a wrapper's bin name when the command name differs"
pass "migration preserves package and bin names"

grep -qF 'exec mise x "npm:@kitlangton/ghui" -- "ghui" "$@"' "$bin_dir/ghui" ||
  fail "migration preserves a scoped npm package name"
pass "migration preserves a scoped npm package name"

grep -qF 'mise use -g --quiet "github:someone/custom-tool" || exit 1' "$bin_dir/custom-tool" ||
  fail "migration rewrites a wrapper on the pre-export template"
grep -qF 'export MISE_MINIMUM_RELEASE_AGE=0' "$bin_dir/custom-tool" ||
  fail "migration brings a pre-export wrapper up to the current template"
pass "migration rewrites wrappers on the pre-export template"

grep -qF 'mise use -g --quiet "npm:some/tool" || exit 1' "$bin_dir/mise-exec-era" ||
  fail "migration rewrites a wrapper on the mise-exec template"
grep -qF 'exec mise x "npm:some/tool" -- "tool-bin" "$@"' "$bin_dir/mise-exec-era" ||
  fail "migration keeps the bin name from a mise-exec wrapper"
grep -qF 'mise use -g --quiet "aqua:some/other" || exit 1' "$bin_dir/bare-exec-era" ||
  fail "migration rewrites a wrapper on the bare-exec template"
grep -qF 'exec mise x "aqua:some/other" -- "other-bin" "$@"' "$bin_dir/bare-exec-era" ||
  fail "migration keeps the bin name from a bare-exec wrapper"
pass "migration rewrites every generated form that predates --quiet"

[[ -x $bin_dir/claude ]] || fail "migration leaves the rewritten wrapper executable"
pass "migration leaves the rewritten wrapper executable"

# Running twice must not touch an already-quiet wrapper.
before=$(cat "$bin_dir/claude")
run_migration
[[ $(cat "$bin_dir/claude") == "$before" ]] || fail "migration is idempotent"
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
[[ $(stat -c%s "$bin_dir/uv") -eq 5000000 ]] || fail "migration leaves a native binary alone"
pass "migration only rewrites wrappers it recognizes"

# A machine with no ~/.local/bin at all must not fail the run.
empty_home="$test_dir/empty-home"
mkdir -p "$empty_home"
HOME="$empty_home" PATH="$ROOT/bin:$PATH" bash -euo pipefail "$migration" >/dev/null ||
  fail "migration succeeds when ~/.local/bin is missing"
pass "migration succeeds when ~/.local/bin is missing"
