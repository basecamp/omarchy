#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command python3

migration="$ROOT/migrations/1787219051.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/bin"

cat >"$test_dir/bin/omarchy-restart-herdr" <<'STUB'
#!/bin/bash

echo reload >>"$HERDR_RELOADS"
STUB

chmod +x "$test_dir/bin/"*

export HERDR_RELOADS="$test_dir/herdr-reloads"

home="$test_dir/home"
config="$home/.config/herdr/config.toml"

run_migration() {
  : >"$HERDR_RELOADS"
  HOME="$home" PATH="$test_dir/bin:$PATH" bash -euo pipefail "$migration" >/dev/null
}

write_config() {
  rm -rf "$home"
  mkdir -p "$home/.config/herdr"
  cat >"$config"
}

# The shipped config minus the new key is what every machine installed before
# this migration has on disk.
write_shipped_without_key() {
  rm -rf "$home"
  mkdir -p "$home/.config/herdr"
  grep -v '^status_indicators' "$ROOT/config/herdr/config.toml" >"$config"
}

# herdr rejects an unknown status_indicators variant, so the value matters as
# much as the file parsing.
indicator() {
  python3 - "$config" <<'PY'
import sys, tomllib
with open(sys.argv[1], 'rb') as handle:
    print(tomllib.load(handle).get('ui', {}).get('status_indicators', ''))
PY
}

ui_headers() {
  grep -cE '^[[:space:]]*\[ui\][[:space:]]*(#.*)?$' "$config"
}

# ------------------------------------------------------------------ shipped default

[[ $(grep -c '^status_indicators = "symbols"$' "$ROOT/config/herdr/config.toml") == 1 ]] ||
  fail "shipped config asks herdr for symbol indicators"
pass "shipped config asks herdr for symbol indicators"

# ------------------------------------------------------------------ existing install

write_shipped_without_key
run_migration

[[ $(indicator) == "symbols" ]] || fail "migration sets symbols on an existing config" "$(indicator)"
pass "migration sets symbols on an existing config"

(($(ui_headers) == 1)) || fail "migration leaves a single [ui] table" "$(ui_headers)"
pass "migration leaves a single [ui] table"

(($(wc -l <"$HERDR_RELOADS") == 1)) || fail "migration reloads herdr once it has changed the config"
pass "migration reloads herdr once it has changed the config"

before=$(sha256sum "$config")
run_migration
[[ $before == $(sha256sum "$config") ]] || fail "migration is idempotent"
pass "migration is idempotent"

# ------------------------------------------------------------------ a chosen value

# Indented because TOML allows it, and a user who picked dots keeps dots.
write_config <<'CONFIG'
[ui]
  status_indicators = "dots"
CONFIG
run_migration

[[ $(indicator) == "dots" ]] || fail "migration leaves a chosen value alone" "$(indicator)"
(($(wc -l <"$HERDR_RELOADS") == 0)) || fail "migration does not reload herdr when it changes nothing"
pass "migration leaves a chosen value alone"

# A key that merely starts the same is not the setting.
write_config <<'CONFIG'
[ui]
status_indicators_extra = "unused"
CONFIG
run_migration

[[ $(indicator) == "symbols" ]] || fail "migration reads whole keys, not prefixes" "$(indicator)"
pass "migration reads whole keys, not prefixes"

# ------------------------------------------------------------------ hand-edited headers

# A trailing comment on the header is valid TOML, and appending a second [ui]
# table for it would leave the config unparseable.
write_config <<'CONFIG'
[ui] # appearance
accent = "blue"
CONFIG
run_migration

[[ $(indicator) == "symbols" ]] || fail "migration finds a commented [ui] header" "$(indicator)"
(($(ui_headers) == 1)) || fail "migration does not duplicate a commented [ui] header" "$(ui_headers)"
pass "migration finds a commented [ui] header"

# ------------------------------------------------------------------ no [ui] table

# [ui.toast] is a different table, so the migration still has to open [ui].
write_config <<'CONFIG'
[theme]
name = "terminal"

[ui.toast]
delivery = "off"
CONFIG
run_migration

[[ $(indicator) == "symbols" ]] || fail "migration opens a [ui] table when there is none" "$(indicator)"
pass "migration opens a [ui] table when there is none"

# ------------------------------------------------------------------ no config

rm -rf "$home"
mkdir -p "$home"
run_migration

[[ -e $config ]] && fail "migration leaves an uninstalled herdr alone"
(($(wc -l <"$HERDR_RELOADS") == 0)) || fail "migration does not reload herdr it never configured"
pass "migration leaves an uninstalled herdr alone"
