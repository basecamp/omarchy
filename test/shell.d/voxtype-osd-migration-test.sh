#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1787257711.sh"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

stub_bin="$tmpdir/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/systemctl" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$stub_bin/systemctl"

run_migration() {
  PATH="$stub_bin:$PATH" HOME="$1" bash -euo pipefail "$migration" >/dev/null
}

missing_section_home="$tmpdir/missing-section"
mkdir -p "$missing_section_home/.config/voxtype"
printf 'state_file = "auto"\n' >"$missing_section_home/.config/voxtype/config.toml"
run_migration "$missing_section_home"
run_migration "$missing_section_home"
(( $(grep -c '^\[osd\]$' "$missing_section_home/.config/voxtype/config.toml") == 1 )) ||
  fail "voxtype OSD migration is idempotent"
grep -A1 '^\[osd\]$' "$missing_section_home/.config/voxtype/config.toml" | grep -qx 'enabled = false' ||
  fail "voxtype OSD migration appends a disabled OSD section"
pass "voxtype OSD migration appends a disabled OSD section once"

empty_section_home="$tmpdir/empty-section"
mkdir -p "$empty_section_home/.config/voxtype"
printf '[osd]\n\n[text]\nspoken_punctuation = false\n' >"$empty_section_home/.config/voxtype/config.toml"
run_migration "$empty_section_home"
sed -n '/^\[osd\]$/,/^\[text\]$/p' "$empty_section_home/.config/voxtype/config.toml" | grep -qx 'enabled = false' ||
  fail "voxtype OSD migration fills an existing OSD section"
pass "voxtype OSD migration fills an existing OSD section"

implicit_forms=(
  $'osd.position = "bottom"\n[text]\nspoken_punctuation = false\n'
  $'osd = { position = "bottom" }\n'
)

for index in "${!implicit_forms[@]}"; do
  implicit_home="$tmpdir/implicit-$index"
  mkdir -p "$implicit_home/.config/voxtype"
  config="$implicit_home/.config/voxtype/config.toml"
  printf '%s' "${implicit_forms[$index]}" >"$config"
  run_migration "$implicit_home"
  python3 -c 'import sys, tomllib; data = tomllib.load(open(sys.argv[1], "rb")); assert data["osd"] == {"position": "bottom", "enabled": False}' "$config" ||
    fail "voxtype OSD migration disables implicit TOML form $index"
done
pass "voxtype OSD migration disables dotted and inline TOML preferences"

explicit_forms=(
  $'[osd]\nenabled = true\n'
  $'["osd"]\n"enabled" = true\n'
  $'osd.enabled = true\n'
  $'osd = { enabled = true }\n'
)

for index in "${!explicit_forms[@]}"; do
  explicit_home="$tmpdir/explicit-$index"
  mkdir -p "$explicit_home/.config/voxtype"
  config="$explicit_home/.config/voxtype/config.toml"
  printf '%s' "${explicit_forms[$index]}" >"$config"
  cp "$config" "$config.expected"
  run_migration "$explicit_home"
  cmp -s "$config.expected" "$config" ||
    fail "voxtype OSD migration preserves explicit TOML form $index"
done
pass "voxtype OSD migration preserves explicit TOML preferences"
