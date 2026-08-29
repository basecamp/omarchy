#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

tmpdir=$(mktemp -d) && [[ -n $tmpdir && -d $tmpdir ]] ||
  fail "the test gets a temporary directory to stub Herdr in"
trap 'rm -rf "$tmpdir"' EXIT

stub_bin="$tmpdir/bin"
mkdir -p "$stub_bin"

# Herdr has no CLI that dumps resolved bindings. The menu reads
# `herdr --default-config` for the action order and default chords, then
# overlays the user config. Stub the binary so this file does not need a
# real Herdr install.
cat >"$stub_bin/herdr" <<'EOF'
#!/bin/bash
if [[ $1 == --default-config ]]; then
  cat <<'CONFIG'
# [keys]
# prefix = "ctrl+b"
# help = "prefix+?"
# detach = "prefix+q"
# new_tab = "prefix+c"
CONFIG
  exit 0
fi
echo "unexpected herdr invocation: $*" >&2
exit 1
EOF
chmod +x "$stub_bin/herdr"

print_keybindings() {
  env -i PATH="$stub_bin:$ROOT/bin:$PATH" HOME="$tmpdir/home" \
    OMARCHY_PATH="$ROOT" \
    bash "$ROOT/bin/omarchy-menu-herdr-keybindings" --print --config "$1"
}

user_config="$tmpdir/config.toml"
cat >"$user_config" <<'EOF'
[keys]
prefix = "ctrl+space"
help = "prefix+?"
detach = "prefix+d"
new_tab = "prefix+c"
EOF

rendered=$(print_keybindings "$user_config")
[[ -n $rendered ]] || fail "the herdr keybindings menu renders from a stubbed default config" "$rendered"

expected_prefix=$(printf '%-32s → %s' "CTRL + SPACE" "PREFIX")
first_line=$(head -n1 <<<"$rendered")
[[ $first_line == "$expected_prefix" ]] ||
  fail "the PREFIX chord is the first command row" "$rendered"
pass "the PREFIX chord is the first command row"

grep -q 'PREFIX + ?  *→ Help' <<<"$rendered" ||
  fail "prefix-relative commands keep PREFIX in the chord column" "$rendered"
! grep -q '→ Prefix$' <<<"$rendered" ||
  fail "prefix is not listed again as a later action" "$rendered"
pass "prefix-relative commands follow the PREFIX mapping"

empty_config="$tmpdir/unbound.toml"
cat >"$empty_config" <<'EOF'
[keys]
prefix = ""
help = "prefix+?"
EOF

rendered=$(print_keybindings "$empty_config")
! grep -q '→ PREFIX$' <<<"$rendered" ||
  fail "an unbound prefix is omitted from the listing" "$rendered"
grep -q 'PREFIX + ?  *→ Help' <<<"$rendered" ||
  fail "unbinding prefix does not drop the remaining commands" "$rendered"
pass "an unbound prefix is omitted from the listing"
