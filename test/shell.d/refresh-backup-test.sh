#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

stub_bin="$tmpdir/bin"
root_fs="$tmpdir/fs"
log="$tmpdir/sudo.log"
mkdir -p "$stub_bin" "$root_fs/etc/pacman.d" "$root_fs/boot"
: >"$log"

# Reroots the paths these scripts touch into a tree the test owns, so the real
# /etc and /boot are never in reach, and records what was run.
cat >"$stub_bin/sudo" <<SH
#!/bin/bash

printf 'sudo' >>"$log"
for arg in "\$@"; do
  printf '\t%s' "\$arg" >>"$log"
done
printf '\n' >>"$log"

action=\$1
shift

rerooted=()
for arg in "\$@"; do
  case "\$arg" in
    /etc/* | /boot/*) rerooted+=("$root_fs\$arg") ;;
    *) rerooted+=("\$arg") ;;
  esac
done

case "\$action" in
  cp | mv) command "\$action" "\${rerooted[@]}" ;;
  test) command test "\${rerooted[@]}" ;;
  *) exit 0 ;;
esac
SH
chmod +x "$stub_bin/sudo"

tools_log="$tmpdir/tools.log"
: >"$tools_log"

# omarchy-hook is in this list for a reason worth naming: refresh-pacman calls
# `omarchy-hook pre-refresh-pacman`, which runs ~/.config/omarchy/hooks/<name>
# through bash. Left unstubbed on a machine that has Omarchy on PATH, this test
# would run the developer's own hook and whatever that hook does.
for tool in limine-update limine-snapper-sync omarchy-update omarchy-pkg-add omarchy-hook; do
  cat >"$stub_bin/$tool" <<SH
#!/bin/bash

printf '%s %s\n' "\$(basename "\$0")" "\$*" >>"$tools_log"
exit 0
SH
  chmod +x "$stub_bin/$tool"
done

# HOME is where omarchy-hook looks, so point it somewhere empty as well. The
# stub covers the call, and this covers anything else that reaches for a hook.
home="$tmpdir/home"
mkdir -p "$home"

backups_in() {
  find "$1" -maxdepth 1 -name "$2" | wc -l
}

# refresh-pacman: two runs have to leave two backups, not one overwritten twice.
printf 'first pacman conf\n' >"$root_fs/etc/pacman.conf"
printf 'first mirrorlist\n' >"$root_fs/etc/pacman.d/mirrorlist"

HOME="$home" OMARCHY_PATH="$ROOT" PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-refresh-pacman" stable >/dev/null 2>&1
printf 'second pacman conf\n' >"$root_fs/etc/pacman.conf"
sleep 1
HOME="$home" OMARCHY_PATH="$ROOT" PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-refresh-pacman" stable >/dev/null 2>&1

count=$(backups_in "$root_fs/etc" 'pacman.conf.bak.*')
(( count == 2 )) ||
  fail "two pacman refreshes keep both backups" "got: $count"

grep -rqx 'first pacman conf' "$root_fs/etc"/pacman.conf.bak.* ||
  fail "the first pacman refresh's backup survives the second"

# The mirrorlist is backed up on the same lines and is just as easy to regress
# to a fixed name on its own, so it gets the same checks rather than riding on
# pacman.conf's.
count=$(backups_in "$root_fs/etc/pacman.d" 'mirrorlist.bak.*')
(( count == 2 )) ||
  fail "two pacman refreshes keep both mirrorlist backups" "got: $count"

grep -rqx 'first mirrorlist' "$root_fs/etc/pacman.d"/mirrorlist.bak.* ||
  fail "the first pacman refresh's mirrorlist backup survives the second"

# Both files share one timestamp per run, so a pair stays recognisable as a
# pair. Reading the stamp off each pacman.conf backup and requiring the matching
# mirrorlist proves that, and fails if either side drifts to its own clock.
for backup in "$root_fs/etc"/pacman.conf.bak.*; do
  stamp=${backup##*/pacman.conf.bak.}
  [[ -f $root_fs/etc/pacman.d/mirrorlist.bak.$stamp ]] ||
    fail "each pacman.conf backup has a mirrorlist backup from the same run" \
      "no mirrorlist for stamp $stamp, have: $(find "$root_fs/etc/pacman.d" -name 'mirrorlist.bak.*' -printf '%f ')"
done

pass "two pacman refreshes keep both backups, paired by run"

# A rejected channel must not spend the backups on its way out.
before=$(backups_in "$root_fs/etc" 'pacman.conf.bak.*')
if HOME="$home" OMARCHY_PATH="$ROOT" PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-refresh-pacman" nonsense >/dev/null 2>&1; then
  fail "an unknown channel is refused"
fi
after=$(backups_in "$root_fs/etc" 'pacman.conf.bak.*')
(( before == after )) ||
  fail "an unknown channel writes no backup" "before: $before, after: $after"

pass "an unknown channel is refused before any backup is written"

# The hook call is what makes isolation matter here, so prove the stub is the
# thing that answered it. If refresh-pacman stops calling omarchy-hook this
# fails, which is the point: the day it starts calling something else, this test
# should be looked at again.
grep -q 'omarchy-hook pre-refresh-pacman' "$tools_log" ||
  fail "the omarchy-hook call is answered by the stub, not the real hook" \
    "ran: $(cat "$tools_log")"

pass "the omarchy-hook call is answered by the stub"

# refresh-limine: same rule, and the config it replaces is moved rather than
# copied, so an overwritten backup loses the original outright.
printf 'first limine conf\n' >"$root_fs/boot/limine.conf"
HOME="$home" OMARCHY_PATH="$ROOT" PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-refresh-limine" >/dev/null 2>&1
printf 'second limine conf\n' >"$root_fs/boot/limine.conf"
sleep 1
HOME="$home" OMARCHY_PATH="$ROOT" PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-refresh-limine" >/dev/null 2>&1

count=$(backups_in "$root_fs/boot" 'limine.conf.bak.*')
(( count == 2 )) ||
  fail "two limine refreshes keep both backups" "got: $count"

grep -rqx 'first limine conf' "$root_fs/boot"/limine.conf.bak.* ||
  fail "the first limine refresh's backup survives the second"

pass "two limine refreshes keep both backups"
