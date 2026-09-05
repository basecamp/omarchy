#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

packages="$ROOT/install/omarchy-base.packages"
migration="$ROOT/migrations/1788129995.sh"

grep -qxF omasnap "$packages" || fail "fresh installs include Omasnap"
! grep -qxF tensaku "$packages" || fail "fresh installs no longer include Tensaku"
pass "fresh installs use Omasnap as the screenshot editor"

grep -Fq 'namespace = "^omasnap$"' "$ROOT/default/hypr/apps/screenshot-selection.lua" ||
  fail "Omasnap has a layer rule"
grep -Fq 'no_screen_share = true' "$ROOT/default/hypr/apps/screenshot-selection.lua" ||
  fail "the Omasnap overlay is excluded from screen sharing"
! grep -Fq 'dev.tensaku.Tensaku' "$ROOT/default/hypr/apps/system.lua" ||
  fail "the removed Tensaku window rules are gone"
pass "Hyprland applies Omasnap's overlay policy without stale Tensaku rules"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/omasnap" <<'SH'
#!/bin/bash
printf '%s\t%s\n' "${OMASNAP_SCREENSHOT_DIR:-}" "$*" >>"$OMASNAP_TEST_LOG"
SH
chmod +x "$stub_bin/omasnap"

capture_log="$test_tmp/capture.log"
OMASNAP_TEST_LOG="$capture_log" PATH="$stub_bin:$PATH" \
  "$ROOT/bin/omarchy-capture-screenshot"
[[ $(<"$capture_log") == $'\t' ]] || fail "the default screenshot opens Omasnap without extra arguments"

: >"$capture_log"
OMASNAP_TEST_LOG="$capture_log" OMARCHY_SCREENSHOT_DIR="$test_tmp/legacy-output" PATH="$stub_bin:$PATH" \
  "$ROOT/bin/omarchy-capture-screenshot" windows copy
[[ $(<"$capture_log") == "$test_tmp/legacy-output"$'\twindows --copy' ]] ||
  fail "the screenshot command maps the legacy directory and copy argument to Omasnap"

: >"$capture_log"
OMASNAP_TEST_LOG="$capture_log" OMARCHY_SCREENSHOT_DIR="$test_tmp/legacy-output" OMASNAP_SCREENSHOT_DIR="$test_tmp/native-output" PATH="$stub_bin:$PATH" \
  "$ROOT/bin/omarchy-capture-screenshot" fullscreen save
[[ $(<"$capture_log") == "$test_tmp/native-output"$'\tfullscreen --save' ]] ||
  fail "the native Omasnap directory wins while legacy save syntax still works"

: >"$capture_log"
OMASNAP_TEST_LOG="$capture_log" PATH="$stub_bin:$PATH" \
  "$ROOT/bin/omarchy-capture-screenshot" region slurp
[[ $(<"$capture_log") == $'\tregion' ]] || fail "the former default slurp argument remains a harmless compatibility no-op"

: >"$capture_log"
OMASNAP_TEST_LOG="$capture_log" PATH="$stub_bin:$PATH" \
  "$ROOT/bin/omarchy-capture-screenshot" scroll --save
[[ $(<"$capture_log") == $'\tscroll --save' ]] || fail "native Omasnap modes and flags pass through unchanged"

pass "the Omarchy screenshot route delegates compatible arguments to Omasnap"

cat >"$stub_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
printf 'add\t%s\n' "$*" >>"$OMASNAP_MIGRATION_LOG"
SH
cat >"$stub_bin/omarchy-pkg-drop" <<'SH'
#!/bin/bash
printf 'drop\t%s\n' "$*" >>"$OMASNAP_MIGRATION_LOG"
SH
chmod +x "$stub_bin/omarchy-pkg-add" "$stub_bin/omarchy-pkg-drop"

migration_home="$test_tmp/home"
mkdir -p "$migration_home/.config/imv" "$migration_home/dotfiles"
cat >"$migration_home/dotfiles/imv.config" <<'EOF'
[binds]

# Edit the current image in Tensaku and quit the viewer
<Ctrl+e> = exec tensaku-edit "$imv_current_file" & ; quit
<Ctrl+x> = exec custom-editor "$imv_current_file" & ; quit
EOF
ln -s "$migration_home/dotfiles/imv.config" "$migration_home/.config/imv/config"

migration_log="$test_tmp/migration.log"
OMASNAP_MIGRATION_LOG="$migration_log" HOME="$migration_home" PATH="$stub_bin:$PATH" \
  bash -euo pipefail "$migration" >/dev/null

[[ $(sed -n '1p' "$migration_log") == $'add\tomasnap' ]] || fail "the migration installs Omasnap first"
[[ $(sed -n '2p' "$migration_log") == $'drop\ttensaku' ]] || fail "the migration removes Tensaku after Omasnap is ready"
grep -Fq '# Edit the current image in Omasnap and quit the viewer' "$migration_home/.config/imv/config" ||
  fail "the migration updates the stock imv editor comment"
grep -Fq '<Ctrl+e> = exec omasnap "$imv_current_file" & ; quit' "$migration_home/.config/imv/config" ||
  fail "the migration sends the stock imv edit binding to Omasnap"
grep -Fq '<Ctrl+x> = exec custom-editor "$imv_current_file" & ; quit' "$migration_home/.config/imv/config" ||
  fail "the migration preserves custom imv bindings"
[[ -L $migration_home/.config/imv/config ]] || fail "the migration preserves a dotfile-managed imv symlink"
[[ $(stat -c '%a' "$migration") == 644 ]] || fail "the Omasnap migration has mode 0644"

pass "the migration swaps packages and safely updates only the stock imv binding"
