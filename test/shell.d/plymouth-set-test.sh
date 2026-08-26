#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

source_dir="$test_tmp/source"
theme_dir="$test_tmp/theme"

mkdir -m 0700 "$source_dir"
mkdir -m 0755 "$theme_dir"
touch "$source_dir/logo.png"

cp -a --no-preserve=mode,ownership "$source_dir/." "$theme_dir/"

[[ $(stat -c %a "$theme_dir") == "755" ]] ||
  fail "Plymouth asset copy preserves the theme directory permissions"

grep -Fq \
  'cp -a --no-preserve=mode,ownership "$staging_dir/." "$theme_dir/"' \
  "$ROOT/bin/omarchy-plymouth-set" ||
  fail "omarchy-plymouth-set avoids copying staging directory ownership and mode"

pass "Plymouth asset copy preserves the package-owned directory metadata"

# omarchy-plymouth-set-by-theme hands over a theme's unlock.png from
# ~/.config/omarchy/themes, and both copies below land in world-readable
# /usr/share, so a symlink there would republish whatever it points at.
secret="$test_tmp/secret"
printf 'not yours\n' >"$secret"
ln -s "$secret" "$test_tmp/logo-link.png"

output=$(OMARCHY_PATH="$ROOT" bash "$ROOT/bin/omarchy-plymouth-set" '#1d2021' '#ebdbb2' "$test_tmp/logo-link.png" 2>&1)
status=$?

(( status != 0 )) || fail "omarchy-plymouth-set refuses a symlinked logo"
[[ $output == *"symlink"* ]] || fail "omarchy-plymouth-set says why it refused the logo" "$output"

grep -Fq 'sudo cp "$staging_dir/logo.png" "$sddm_dir/logo.png"' "$ROOT/bin/omarchy-plymouth-set" ||
  fail "omarchy-plymouth-set copies the staged logo to SDDM rather than rereading the caller's path as root"

pass "a themed logo cannot republish a file it merely points at"

# White's background is #ffffff. The text color is #000000. A second sed that
# rewrites leftover #ffffff into the text color paints the background we just
# wrote, and the greeter goes black-on-black (#7115).
sddm_from() {
  local src=$1 bg=$2 text=$3 file=$4
  bash -c '
    source "$1" || exit 1
    sddm_qml_with_colors "$2" "$3" "$4"
  ' bash "$src" "$bg" "$text" "$file"
}

template="$ROOT/default/sddm/omarchy/Main.qml"
grep -Fq 'color: "#1a1b26"' "$template" ||
  fail "SDDM template still uses #1a1b26 as the background placeholder"
if grep -Fq '#ffffff' "$template"; then
  fail "SDDM template has no #ffffff of its own — that is why the second sed was dead until it ate the background"
fi

fixture_both="$test_tmp/both-placeholders.qml"
printf '%s\n' 'color: "#1a1b26"' 'text: "#ffffff"' >"$fixture_both"

fixture_twice="$test_tmp/two-backgrounds.qml"
printf '%s\n' 'pair: "#1a1b26" and "#1a1b26"' >"$fixture_twice"

fixture_twice_text="$test_tmp/two-texts.qml"
printf '%s\n' 'pair: "#ffffff" and "#ffffff"' >"$fixture_twice_text"

prove_sddm_helper() {
  local src=$1
  local qml both inverse twice

  qml=$(sddm_from "$src" ffffff 000000 "$template") || return 1
  [[ $qml == *$'\n  color: "#ffffff"\n'* ]] || return 1
  [[ $qml != *__OMARCHY_SDDM_* ]] || return 1

  qml=$(sddm_from "$src" 1a1b26 c0caf5 "$template") || return 1
  [[ $qml == *$'\n  color: "#1a1b26"\n'* ]] || return 1

  qml=$(sddm_from "$src" FFFCF0 100F0F "$template") || return 1
  [[ $qml == *$'\n  color: "#FFFCF0"\n'* ]] || return 1

  both=$(sddm_from "$src" ffffff 000000 "$fixture_both") || return 1
  [[ $both == *'color: "#ffffff"'* ]] || return 1
  [[ $both == *'text: "#000000"'* ]] || return 1
  [[ $both != *__OMARCHY_SDDM_* ]] || return 1

  inverse=$(sddm_from "$src" 111111 1a1b26 "$fixture_both") || return 1
  [[ $inverse == *'color: "#111111"'* ]] || return 1
  [[ $inverse == *'text: "#1a1b26"'* ]] || return 1
  [[ $inverse != *__OMARCHY_SDDM_* ]] || return 1

  twice=$(sddm_from "$src" abcdef 000000 "$fixture_twice") || return 1
  [[ $twice == *'#abcdef" and "#abcdef"'* ]] || return 1
  [[ $twice != *__OMARCHY_SDDM_* ]] || return 1

  twice=$(sddm_from "$src" 111111 abcdef "$fixture_twice_text") || return 1
  [[ $twice == *'#abcdef" and "#abcdef"'* ]] || return 1
  [[ $twice != *__OMARCHY_SDDM_* ]] || return 1
  return 0
}

prove_sddm_helper "$ROOT/bin/omarchy-plymouth-set" ||
  fail "production SDDM color helper holds the color contracts"
grep -Fq 'sddm_qml_with_colors "$bg_hex" "$text_hex" "$sddm_template"' "$ROOT/bin/omarchy-plymouth-set" ||
  fail "SDDM write goes through sddm_qml_with_colors"
if grep -Fq 's/#1a1b26/#$bg_hex/g' "$ROOT/bin/omarchy-plymouth-set"; then
  fail "production rewrite no longer substitutes background color in one pass"
fi
if grep -Fq 's/#ffffff/#$text_hex/g' "$ROOT/bin/omarchy-plymouth-set"; then
  fail "production rewrite no longer substitutes text color in one pass"
fi
pass "White unlock does not paint the SDDM background black"

write_mutant() {
  cat >"$1"
}

mutant_killed() {
  local name=$1
  local file=$2
  if prove_sddm_helper "$file" 2>/dev/null; then
    fail "mutant survived: $name"
  fi
  pass "mutant killed: $name"
}

write_mutant "$test_tmp/m-original-two-pass.sh" <<'EOF'
sddm_qml_with_colors() {
  local bg_hex=$1 text_hex=$2 template=$3
  sed \
    -e "s/#1a1b26/#$bg_hex/g" \
    -e "s/#ffffff/#$text_hex/g" \
    "$template"
}
EOF
mutant_killed "original two-pass sed (#7115)" "$test_tmp/m-original-two-pass.sh"

write_mutant "$test_tmp/m-swap-order.sh" <<'EOF'
sddm_qml_with_colors() {
  local bg_hex=$1 text_hex=$2 template=$3
  sed \
    -e "s/#ffffff/#$text_hex/g" \
    -e "s/#1a1b26/#$bg_hex/g" \
    "$template"
}
EOF
mutant_killed "swap-order sed without tokens" "$test_tmp/m-swap-order.sh"

write_mutant "$test_tmp/m-tokens-last.sh" <<'EOF'
sddm_qml_with_colors() {
  local bg_hex=$1 text_hex=$2 template=$3
  sed \
    -e "s/#__OMARCHY_SDDM_BG__/#$bg_hex/g" \
    -e "s/#__OMARCHY_SDDM_TEXT__/#$text_hex/g" \
    -e "s/#1a1b26/#__OMARCHY_SDDM_BG__/g" \
    -e "s/#ffffff/#__OMARCHY_SDDM_TEXT__/g" \
    "$template"
}
EOF
mutant_killed "token replace before placeholders exist" "$test_tmp/m-tokens-last.sh"

write_mutant "$test_tmp/m-no-global.sh" <<'EOF'
sddm_qml_with_colors() {
  local bg_hex=$1 text_hex=$2 template=$3
  sed \
    -e "s/#1a1b26/#__OMARCHY_SDDM_BG__/" \
    -e "s/#ffffff/#__OMARCHY_SDDM_TEXT__/" \
    -e "s/#__OMARCHY_SDDM_BG__/#$bg_hex/" \
    -e "s/#__OMARCHY_SDDM_TEXT__/#$text_hex/" \
    "$template"
}
EOF
mutant_killed "first-match-only substitutions" "$test_tmp/m-no-global.sh"

write_mutant "$test_tmp/m-no-hash.sh" <<'EOF'
sddm_qml_with_colors() {
  local bg_hex=$1 text_hex=$2 template=$3
  sed \
    -e "s/#1a1b26/#__OMARCHY_SDDM_BG__/g" \
    -e "s/#ffffff/#__OMARCHY_SDDM_TEXT__/g" \
    -e "s/#__OMARCHY_SDDM_BG__/$bg_hex/g" \
    -e "s/#__OMARCHY_SDDM_TEXT__/$text_hex/g" \
    "$template"
}
EOF
mutant_killed "dropping the # from the written color" "$test_tmp/m-no-hash.sh"

write_mutant "$test_tmp/m-no-global-text.sh" <<'EOF'
sddm_qml_with_colors() {
  local bg_hex=$1 text_hex=$2 template=$3
  sed \
    -e "s/#1a1b26/#__OMARCHY_SDDM_BG__/g" \
    -e "s/#ffffff/#__OMARCHY_SDDM_TEXT__/" \
    -e "s/#__OMARCHY_SDDM_BG__/#$bg_hex/g" \
    -e "s/#__OMARCHY_SDDM_TEXT__/#$text_hex/" \
    "$template"
}
EOF
mutant_killed "first-match-only text substitutions" "$test_tmp/m-no-global-text.sh"

write_mutant "$test_tmp/m-shared-token.sh" <<'EOF'
sddm_qml_with_colors() {
  local bg_hex=$1 text_hex=$2 template=$3
  sed \
    -e "s/#1a1b26/#__OMARCHY_SDDM__/g" \
    -e "s/#ffffff/#__OMARCHY_SDDM__/g" \
    -e "s/#__OMARCHY_SDDM__/#$bg_hex/g" \
    -e "s/#__OMARCHY_SDDM__/#$text_hex/g" \
    "$template"
}
EOF
mutant_killed "shared token so the last color wins" "$test_tmp/m-shared-token.sh"

write_mutant "$test_tmp/m-bg-token-then-eat.sh" <<'EOF'
sddm_qml_with_colors() {
  local bg_hex=$1 text_hex=$2 template=$3
  sed \
    -e "s/#1a1b26/#__OMARCHY_SDDM_BG__/g" \
    -e "s/#__OMARCHY_SDDM_BG__/#$bg_hex/g" \
    -e "s/#ffffff/#$text_hex/g" \
    "$template"
}
EOF
mutant_killed "token the background then still eat leftover #ffffff" "$test_tmp/m-bg-token-then-eat.sh"

write_mutant "$test_tmp/m-swapped-args.sh" <<'EOF'
sddm_qml_with_colors() {
  local bg_hex=$2 text_hex=$1 template=$3
  sed \
    -e "s/#1a1b26/#__OMARCHY_SDDM_BG__/g" \
    -e "s/#ffffff/#__OMARCHY_SDDM_TEXT__/g" \
    -e "s/#__OMARCHY_SDDM_BG__/#$bg_hex/g" \
    -e "s/#__OMARCHY_SDDM_TEXT__/#$text_hex/g" \
    "$template"
}
EOF
mutant_killed "paint background with the text color" "$test_tmp/m-swapped-args.sh"
