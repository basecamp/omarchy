#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

home="$tmpdir/home"
omarchy_path="$tmpdir/omarchy"

mkdir -p "$home/.config/hypr" "$omarchy_path/config/hypr"

cat >"$omarchy_path/config/hypr/bindings.lua" <<'EOF'
-- refreshed from OMARCHY_PATH
EOF

cat >"$home/.config/hypr/bindings.lua" <<'EOF'
-- existing user config
EOF

HOME="$home" OMARCHY_PATH="$omarchy_path" "$ROOT/bin/omarchy-refresh-config" hypr/bindings.lua >/dev/null

cmp -s "$omarchy_path/config/hypr/bindings.lua" "$home/.config/hypr/bindings.lua" ||
  fail "refresh-config copies from OMARCHY_PATH/config"

backup=$(find "$home/.config/hypr" -name 'bindings.lua.bak.*' -print -quit)
[[ -n $backup ]] || fail "refresh-config backs up replaced user config"
grep -Fq -- '-- existing user config' "$backup" ||
  fail "refresh-config backup contains previous user config"

pass "refresh-config copies from OMARCHY_PATH/config and backs up existing files"

if HOME="$home" OMARCHY_PATH="$omarchy_path" "$ROOT/bin/omarchy-refresh-config" hypr/missing.lua >"$tmpdir/out" 2>"$tmpdir/err"; then
  fail "refresh-config rejects configs missing from OMARCHY_PATH/config"
fi

grep -Fq 'Not a shipped user config: hypr/missing.lua' "$tmpdir/err" ||
  fail "refresh-config reports missing shipped config"

pass "refresh-config validates against OMARCHY_PATH/config"

# A backup that cannot be written has to stop the refresh. Before this, the
# second copy went ahead anyway: the user's file was replaced by the default,
# and the message went on to name a backup that was never written.
guard_home="$tmpdir/guard-home"
mkdir -p "$guard_home/.config/hypr"
printf -- '-- precious user config\n' >"$guard_home/.config/hypr/bindings.lua"

real_cp=$(command -v cp)
nobackup_bin="$tmpdir/bin-nobackup"
mkdir -p "$nobackup_bin"

cat >"$nobackup_bin/cp" <<SH
#!/bin/bash

# Fail only the backup copy, which is the one writing a .bak. destination.
case "\${!#}" in
  *.bak.*) exit 1 ;;
esac

exec "$real_cp" "\$@"
SH
chmod +x "$nobackup_bin/cp"

if HOME="$guard_home" OMARCHY_PATH="$omarchy_path" PATH="$nobackup_bin:$PATH" \
  "$ROOT/bin/omarchy-refresh-config" hypr/bindings.lua >"$tmpdir/guard-out" 2>"$tmpdir/guard-err"; then
  fail "refresh-config stops when the backup cannot be written"
fi

grep -Fq -- '-- precious user config' "$guard_home/.config/hypr/bindings.lua" ||
  fail "refresh-config leaves the user config in place when the backup fails" \
    "got: $(cat "$guard_home/.config/hypr/bindings.lua")"

grep -Fq 'Could not back up' "$tmpdir/guard-err" ||
  fail "refresh-config says why it stopped" "got: $(cat "$tmpdir/guard-err")"

pass "refresh-config leaves the user config alone when the backup fails"

# Two refreshes of the same file in the same second landed on one backup name,
# and the second copy overwrote the first one's backup. The clock is pinned
# here so the collision is certain rather than a matter of timing.
clash_home="$tmpdir/clash-home"
mkdir -p "$clash_home/.config/hypr"

clock_bin="$tmpdir/bin-clock"
mkdir -p "$clock_bin"

cat >"$clock_bin/date" <<'SH'
#!/bin/bash

printf '1700000000\n'
SH
chmod +x "$clock_bin/date"

for content in first second; do
  printf -- '-- %s user config\n' "$content" >"$clash_home/.config/hypr/bindings.lua"
  HOME="$clash_home" OMARCHY_PATH="$omarchy_path" PATH="$clock_bin:$PATH" \
    "$ROOT/bin/omarchy-refresh-config" hypr/bindings.lua >/dev/null
done

backups=$(find "$clash_home/.config/hypr" -name 'bindings.lua.bak.*' | wc -l)
(( backups == 2 )) ||
  fail "two refreshes in the same second keep both backups" "got: $backups"

pass "two refreshes in the same second keep both backups"
