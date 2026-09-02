#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command fc-match

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_dir="$test_tmp/bin"
font_home="$test_tmp/home"
mkdir -p "$stub_dir" "$font_home" "$test_tmp/cache"

for command_name in omarchy-hook omarchy-notification-send omarchy-restart-shell; do
  printf '#!/bin/bash\nexit 0\n' >"$stub_dir/$command_name"
  chmod +x "$stub_dir/$command_name"
done

HOME="$font_home" PATH="$stub_dir:$PATH" \
  "$ROOT/bin/omarchy-font-set" "Liberation Mono" >/dev/null

user_config="$font_home/.config/fontconfig/fonts.conf"
grep -Fq '<test name="family" qual="first">' "$user_config" ||
  fail "font selection limits its override to generic requests" "$(cat "$user_config")"
grep -Fq '<edit name="family" mode="assign" binding="strong">' "$user_config" ||
  fail "font selection makes the selected family authoritative" "$(cat "$user_config")"
grep -Fq '<string>Liberation Mono</string>' "$user_config" ||
  fail "font selection records the selected family" "$(cat "$user_config")"
pass "font selection writes a scoped user override"

package_config="$test_tmp/package.conf"
cat >"$package_config" <<XML
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <dir>/usr/share/fonts</dir>
  <cachedir>$test_tmp/cache</cachedir>
  <include>$ROOT/default/fontconfig/conf.avail/50-omarchy.conf</include>
</fontconfig>
XML

combined_config="$test_tmp/combined.conf"
cat >"$combined_config" <<XML
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <dir>/usr/share/fonts</dir>
  <cachedir>$test_tmp/cache</cachedir>
  <include>$ROOT/default/fontconfig/conf.avail/50-omarchy.conf</include>
  <include>$user_config</include>
</fontconfig>
XML

resolved_family() {
  local config="$1"
  local pattern="$2"

  FONTCONFIG_FILE="$config" fc-match --format '%{family}\n' "$pattern"
}

family=$(resolved_family "$package_config" monospace)
[[ $family == "JetBrainsMono Nerd Font"* ]] ||
  fail "packaged monospace font remains the default" "resolved family: $family"
pass "packaged monospace font remains the default"

family=$(resolved_family "$combined_config" monospace)
[[ $family == "Liberation Mono" ]] ||
  fail "selected monospace font overrides the packaged default" "resolved family: $family"
pass "selected monospace font overrides the packaged default"

family=$(resolved_family "$combined_config" "JetBrainsMono Nerd Font,monospace")
[[ $family == "JetBrainsMono Nerd Font"* ]] ||
  fail "an explicit application font overrides the user preference" "resolved family: $family"
pass "an explicit application font overrides the user preference"

write_legacy_config() {
  local target="$1"

  mkdir -p "$(dirname "$target")"
  cat >"$target" <<'XML'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <match target="pattern">
    <test name="family" qual="any">
      <string>monospace</string>
    </test>
    <edit name="family" mode="prepend_first" binding="strong">
      <string>Liberation Mono</string>
    </edit>
  </match>
</fontconfig>
XML
}

migration="$ROOT/migrations/1788373531.sh"
migration_home="$test_tmp/migration-home"
migration_config="$migration_home/.config/fontconfig/fonts.conf"
write_legacy_config "$migration_config"
chmod 600 "$migration_config"

HOME="$migration_home" bash -euo pipefail "$migration" >/dev/null
grep -Fq '<test name="family" qual="first">' "$migration_config" ||
  fail "migration updates the generated legacy config" "$(cat "$migration_config")"
grep -Fq '<string>Liberation Mono</string>' "$migration_config" ||
  fail "migration preserves the selected font" "$(cat "$migration_config")"
[[ $(stat -c '%a' "$migration_config") == 600 ]] ||
  fail "migration preserves the config file mode" "$(stat -c '%a' "$migration_config")"
pass "migration updates the generated config and preserves its mode"

before=$(sha256sum "$migration_config")
HOME="$migration_home" bash -euo pipefail "$migration" >/dev/null
[[ $before == "$(sha256sum "$migration_config")" ]] ||
  fail "fontconfig migration is idempotent" "$(cat "$migration_config")"
pass "fontconfig migration is idempotent"

custom_home="$test_tmp/custom-home"
custom_config="$custom_home/.config/fontconfig/fonts.conf"
write_legacy_config "$custom_config"
sed -i '/<\/fontconfig>/i\  <!-- Keep my custom configuration. -->' "$custom_config"
before=$(sha256sum "$custom_config")
HOME="$custom_home" bash -euo pipefail "$migration" >/dev/null
[[ $before == "$(sha256sum "$custom_config")" ]] ||
  fail "migration leaves customized configs alone" "$(cat "$custom_config")"
pass "migration leaves customized configs alone"
