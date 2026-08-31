#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

migration="$ROOT/migrations/1788139189.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

home="$test_dir/home"
current_theme_dir="$home/.local/state/omarchy/current/theme"
current_colors="$current_theme_dir/colors.toml"
mkdir -p "$current_theme_dir"

stub_bin="$test_dir/bin"
mkdir -p "$stub_bin"
refresh_called="$test_dir/refresh-called"

cat >"$stub_bin/omarchy-theme-refresh" <<STUB
#!/bin/bash
touch "$refresh_called"
STUB
chmod +x "$stub_bin/omarchy-theme-refresh"

run_migration() {
  rm -f "$refresh_called"
  HOME="$home" PATH="$stub_bin:$PATH" bash -euo pipefail "$migration" >/dev/null
}

# An affected theme has an invisible selection: it exactly matches foreground.
cat >"$current_colors" <<'EOF'
accent = "#336699"
selection = "#f0f0f0"

background = "#101010"
foreground = "#f0f0f0"
EOF
run_migration
[[ -e $refresh_called ]] || fail "migration refreshes a theme whose selection matches foreground"
pass "migration refreshes a theme whose selection matches foreground"

# A healthy theme, where selection differs from foreground, is left alone.
cat >"$current_colors" <<'EOF'
accent = "#336699"
selection = "#222222"

background = "#101010"
foreground = "#f0f0f0"
EOF
run_migration
[[ ! -e $refresh_called ]] || fail "migration leaves a theme whose selection already differs from foreground"
pass "migration leaves a theme whose selection already differs from foreground"

# No current theme (e.g. a fresh install that has not set one yet) is a no-op.
rm -f "$current_colors"
run_migration
[[ ! -e $refresh_called ]] || fail "migration no-ops when there is no current theme"
pass "migration no-ops when there is no current theme"
