#!/bin/bash
# Guards around package-repository signature policy:
#
# 1. install/hardware/pacman.sh must never re-add a repository that disables
#    signature verification outright, and must arm verification for the
#    t2linux repository with the pinned upstream signing key.
# 2. bin/omarchy-upgrade-to-quattro may write the unsigned-package override
#    only to bootstrap the keyring, and must drop it before any further
#    transaction in the upgrade.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=shell.d/base-test.sh
source "$ROOT/test/shell.d/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

# ---------------------------------------------------------------- T2 stanza

fail_guard() {
  fail "$1" "${2-}"
}

# No repository anywhere in the tree may switch verification off outright.
# install/hardware/pacman.sh is exempt from the text scan because it must
# mention SigLevel = Never to reconcile pre-arming installs (comments, the
# detection gate, and the sed that replaces the line); its appended stanza is
# asserted separately below.
if grep -rn 'SigLevel = Never' \
     --exclude=pacman.sh "$ROOT/install" "$ROOT/default" "$ROOT/bin" 2>/dev/null; then
  fail_guard "no repository stanza disables signature verification outright"
fi

# The stanza pacman.sh appends must itself be the armed policy: check the
# heredoc body rather than the whole file.
if sed -n '/cat >> "\$t2_pacman_conf"/,/^EOF$/p' "$ROOT/install/hardware/pacman.sh" |
     grep -q 'SigLevel = Never'; then
  fail_guard "the appended T2 stanza never disables signature verification"
fi
sed -n '/cat >> "\$t2_pacman_conf"/,/^EOF$/p' "$ROOT/install/hardware/pacman.sh" |
  grep -q 'SigLevel = PackageOptional DatabaseNever' ||
  fail_guard "the appended T2 stanza arms verification"
pass "no repository stanza disables signature verification outright"

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"

# A T2 machine reports the Apple T2 PCI vendor:device ids.
cat >"$mock_bin/lspci" <<'SH'
#!/bin/bash
printf '00:1f.0 Communication controller [106b:1801]\n'
SH

# Record pacman-key usage; validate every key argument against the pinned
# fingerprint so a drift or typo cannot silently re-point trust.
cat >"$mock_bin/pacman-key" <<SH
#!/bin/bash
printf '%s\n' "\$*" >>"$test_tmp/pacman-key-calls"
for arg in "\$@"; do
  case "\$arg" in
    [0-9A-F]*) [[ \$arg == 8BE1FEE14302371DEF6F910A0E5877AC225D1980 ]] ||
      { echo "unexpected key: \$arg" >&2; exit 1; } ;;
  esac
done
exit 0
SH

chmod +x "$mock_bin/"*

conf="$test_tmp/pacman.conf"
printf '[options]\nHoldPkg = pacman glibc\n' >"$conf"

run_t2_repo_setup() {
  PATH="$mock_bin:$PATH" OMARCHY_T2_PACMAN_CONF="$conf" \
    bash "$ROOT/install/hardware/pacman.sh"
}

run_t2_repo_setup

grep -q '^\[arch-mact2\]' "$conf" ||
  fail_guard "the T2 repository stanza is written for T2 hardware" "$(cat "$conf")"
grep -q '^SigLevel = PackageOptional DatabaseNever$' "$conf" ||
  fail_guard "the T2 stanza arms verification instead of disabling it" "$(cat "$conf")"
grep -q 'SigLevel = Never' "$conf" &&
  fail_guard "the T2 stanza never carries the old disable-verification line"
grep -q 'keyserver.ubuntu.com' "$test_tmp/pacman-key-calls" ||
  fail_guard "the pinned t2linux key is imported from a keyserver" "$(cat "$test_tmp/pacman-key-calls")"
grep -q -- '--lsign-key' "$test_tmp/pacman-key-calls" ||
  fail_guard "the imported t2linux key is locally signed" "$(cat "$test_tmp/pacman-key-calls")"
pass "the T2 stanza arms verification and pins the upstream signing key"

# A second run must not append a duplicate stanza.
run_t2_repo_setup
[[ $(grep -c '^\[arch-mact2\]' "$conf") == 1 ]] ||
  fail_guard "the T2 stanza is idempotent" "$(cat "$conf")"
pass "the T2 stanza is idempotent"

# An unusable keyserver must refuse to enable the repository rather than fall
# back to an unsigned stanza: failing the install is safer than silently
# running an unauthenticated repository as root.
cat >"$mock_bin/pacman-key" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$mock_bin/pacman-key"

conf2="$test_tmp/pacman-fail.conf"
printf '[options]\n' >"$conf2"
if PATH="$mock_bin:$PATH" OMARCHY_T2_PACMAN_CONF="$conf2" \
    bash "$ROOT/install/hardware/pacman.sh" 2>/dev/null; then
  fail_guard "a failed key import refuses to enable the arch-mact2 repository"
fi
grep -q '^\[arch-mact2\]' "$conf2" &&
  fail_guard "a failed key import leaves no repository stanza behind"
pass "a failed key import refuses to enable the arch-mact2 repository"

# Installs that predate signature arming already carry the stanza with
# SigLevel = Never. The script must reconcile those in place -- import the
# key and upgrade the policy -- rather than skipping them because the stanza
# exists.
cat >"$mock_bin/pacman-key" <<SH
#!/bin/bash
printf '%s\n' "\$*" >>"$test_tmp/pacman-key-calls"
for arg in "\$@"; do
  case "\$arg" in
    [0-9A-F]*) [[ \$arg == 8BE1FEE14302371DEF6F910A0E5877AC225D1980 ]] ||
      { echo "unexpected key: \$arg" >&2; exit 1; } ;;
  esac
done
exit 0
SH
chmod +x "$mock_bin/pacman-key"

conf3="$test_tmp/pacman-legacy.conf"
cat >"$conf3" <<'EOF'
[options]
HoldPkg = pacman glibc

[arch-mact2]
Server = https://github.com/NoaHimesaka1873/arch-mact2-mirror/releases/download/release
SigLevel = Never
EOF
: >"$test_tmp/pacman-key-calls"

run_t2_repo_setup_with() { # $1 = conf path
  PATH="$mock_bin:$PATH" OMARCHY_T2_PACMAN_CONF="$1" \
    bash "$ROOT/install/hardware/pacman.sh"
}

run_t2_repo_setup_with "$conf3"

grep -q '^SigLevel = PackageOptional DatabaseNever$' "$conf3" ||
  fail_guard "a legacy Never stanza is upgraded in place" "$(cat "$conf3")"
grep -q 'SigLevel = Never' "$conf3" &&
  fail_guard "the legacy Never line is gone after reconciliation"
[[ $(grep -c '^\[arch-mact2\]' "$conf3") == 1 ]] ||
  fail_guard "reconciliation does not duplicate the stanza"
grep -q -- '--lsign-key' "$test_tmp/pacman-key-calls" ||
  fail_guard "reconciliation imports and signs the pinned key" "$(cat "$test_tmp/pacman-key-calls")"
pass "a legacy Never stanza is reconciled in place"

# A failed key import during reconciliation cannot fix the machine, but it
# must also not break it: the stanza keeps working exactly as before and the
# script exits zero so the hardware stage continues.
cat >"$mock_bin/pacman-key" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$mock_bin/pacman-key"
cp "$conf3" "$test_tmp/pacman-legacy-fail.conf"
sed -i 's/^SigLevel = PackageOptional DatabaseNever$/SigLevel = Never/' "$test_tmp/pacman-legacy-fail.conf"

if ! PATH="$mock_bin:$PATH" OMARCHY_T2_PACMAN_CONF="$test_tmp/pacman-legacy-fail.conf" \
    bash "$ROOT/install/hardware/pacman.sh" 2>/dev/null; then
  fail_guard "a failed reconciliation import does not fail the hardware stage"
fi
grep -q '^SigLevel = Never$' "$test_tmp/pacman-legacy-fail.conf" ||
  fail_guard "a failed reconciliation leaves the working stanza untouched"
pass "a failed reconciliation import leaves the machine working as it was"

# ------------------------------------------------------------ quattro override

quattro="$ROOT/bin/omarchy-upgrade-to-quattro"

# The override exists only as a keyring bootstrap: it may be written, but the
# script must drop it again before any further transaction.
grep -q 'SigLevel = Optional TrustAll' "$quattro" ||
  fail_guard "the quattro bootstrap override is still written for the keyring install"
grep -q 'require_signed_omarchy_repo()' "$quattro" ||
  fail_guard "quattro defines the override removal step"
grep -q 'SigLevel = Optional TrustAll' "$quattro" &&
  ! sed -n '/^require_signed_omarchy_repo()/,/^}/p' "$quattro" |
      grep -q '/\^SigLevel = Optional TrustAll\$/d' &&
  fail_guard "the removal step deletes the bootstrap override line"

# The removal must run immediately after the keyring install, before any
# package-bearing step.
keyring_line=$(grep -n '^install_keyrings$' "$quattro" | cut -d: -f1)
removal_line=$(grep -n '^require_signed_omarchy_repo$' "$quattro" | cut -d: -f1)
next_line=$((keyring_line + 1))
[[ $removal_line == "$next_line" ]] ||
  fail_guard "the override removal runs immediately after install_keyrings" \
    "install_keyrings at $keyring_line, removal at $removal_line"
pass "quattro drops the bootstrap override right after the keyring install"

# ---------------------------------------------------------------- migration

# Normal updates run migrations, not the hardware installer, so existing T2
# machines are reconciled by a migration with the same fingerprint and the
# same replacement line as the installer.
migration="$ROOT/migrations/1787720000.sh"

grep -q '8BE1FEE14302371DEF6F910A0E5877AC225D1980' "$migration" ||
  fail_guard "the migration pins the same t2linux signing key"
grep -q 'keyserver.ubuntu.com' "$migration" ||
  fail_guard "the migration imports the key from the keyserver"
grep -q -- '--lsign-key' "$migration" ||
  fail_guard "the migration locally signs the imported key"
grep -q 'SigLevel = PackageOptional DatabaseNever' "$migration" ||
  fail_guard "the migration upgrades the stanza to the armed policy"
grep -q "arch_mact2_never='SigLevel = Never'" "$migration" &&
  grep -q '\${arch_mact2_never}' "$migration" &&
  grep -q 'if .*pacman-key' "$migration" ||
  fail_guard "the migration is gated on a legacy Never stanza and a successful import"

# Self-detecting and idempotent by construction: the Never check gates the
# sed, so a rerun after a successful upgrade (or on a machine without the
# stanza) never touches pacman.conf again.
never_line=$(grep -n 'arch_mact2_never}' "$migration" | cut -d: -f1 | head -1)
sed_line=$(grep -n 'sed -i' "$migration" | cut -d: -f1 | head -1)
[[ -n $never_line && -n $sed_line && $sed_line -gt $never_line ]] ||
  fail_guard "the migration only mutates pacman.conf under the Never gate"
pass "the migration reconciles legacy T2 installs with the same pinning"
