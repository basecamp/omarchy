#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

upgrade="$ROOT/bin/omarchy-upgrade-to-quattro"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

pinned=40DFB630FF42BCFFB047046CF0134EE680CAC571

# Write the explicit signature-required repo, locally sign only the exact key,
# and verify Pacman's effective policy before the first sync/install. There is
# no retry under unauthenticated policy.
config_line=$(grep -n '^configure_pacman_channel$' "$upgrade" | tail -1 | cut -d: -f1) ||
  fail "Quattro never configures its signed package source"
bootstrap_line=$(grep -n '^bootstrap_omarchy_packaging_key$' "$upgrade" | tail -1 | cut -d: -f1) ||
  fail "Quattro never invokes its pinned-key bootstrap"
policy_line=$(grep -n '^verify_effective_omarchy_package_policy$' "$upgrade" | tail -1 | cut -d: -f1) ||
  fail "Quattro never verifies Pacman's effective package policy"
transaction_line=$(grep -n '^install_keyrings$' "$upgrade" | tail -1 | cut -d: -f1) ||
  fail "Quattro never reaches the first package transaction"
((config_line < bootstrap_line &&
  bootstrap_line < policy_line && policy_line < transaction_line)) ||
  fail "Quattro signed configuration/key bootstrap precedes every package transaction"
grep -F 'SigLevel = Required DatabaseOptional' "$upgrade" >/dev/null
! grep -F 'SigLevel = Optional TrustAll' "$upgrade" >/dev/null || fail "Quattro writes Optional TrustAll"
install_body=$(sed -n '/^install_keyrings() {/,/^}/p' "$upgrade")
[[ $(grep -c 'pacman -Syy' <<<"$install_body") == 1 ]] || fail "Quattro has an unauthenticated keyring retry"
pass "Quattro repairs policy and establishes pinned trust before its first transaction"

# Exercise the production bootstrap body. A forged fingerprint or failed
# keyserver retrieval exits before local signing; the exact fingerprint signs
# only the pinned identifier.
bootstrap_source=$(sed -n '/^bootstrap_omarchy_packaging_key() {/,/^}/p' "$upgrade")
bootstrap_probe() (
  local first="$1" second="$2" recv_status="$3" log_file="$4" calls=0
  local OMARCHY_PACKAGING_KEY_FINGERPRINT="$pinned"
  log() { :; }
  fail() { exit 97; }
  installed_omarchy_primary_fingerprint() {
    calls=$((calls + 1))
    if ((calls == 1)); then printf '%s' "$first"; else printf '%s' "$second"; fi
  }
  as_root() {
    printf '%s\n' "$*" >>"$log_file"
    [[ $* != *'--recv-keys'* ]] || return "$recv_status"
  }
  eval "$bootstrap_source"
  bootstrap_omarchy_packaging_key
)

: >"$test_tmp/forged.log"
if bootstrap_probe BAD ALSO_BAD 0 "$test_tmp/forged.log"; then
  fail "forged Omarchy fingerprint is accepted"
fi
! grep -q -- '--lsign-key' "$test_tmp/forged.log" || fail "forged key is locally signed"
: >"$test_tmp/bootstrap-fail.log"
if bootstrap_probe BAD '' 1 "$test_tmp/bootstrap-fail.log"; then
  fail "failed Omarchy key bootstrap is accepted"
fi
! grep -q -- '--lsign-key' "$test_tmp/bootstrap-fail.log" || fail "failed bootstrap reaches local signing"
: >"$test_tmp/exact.log"
bootstrap_probe "$pinned" "$pinned" 0 "$test_tmp/exact.log"
grep -Fqx "/usr/bin/pacman-key --lsign-key $pinned" "$test_tmp/exact.log" ||
  fail "exact pinned Omarchy fingerprint is not locally signed"
pass "fingerprint mismatch and bootstrap failure fail before package trust is published"

# Literal-line repair is insufficient when pacman.conf contains Includes or a
# later override. Exercise the exact effective-policy gate used immediately
# before transactions and require both the package verification and trust
# dimensions, with no contradictory token.
policy_stub="$test_tmp/pacman-conf-policy"
cat >"$policy_stub" <<'STUB'
#!/bin/bash
[[ ${TEST_POLICY_STATUS:-0} == 0 ]] || exit "$TEST_POLICY_STATUS"
if [[ " $* " == *" --repo omarchy "* ]]; then
  printf '%s\n' "${TEST_REPO_POLICY-${TEST_POLICY:-}}"
else
  printf '%s\n' "${TEST_GLOBAL_POLICY-${TEST_POLICY:-}}"
fi
STUB
chmod 0755 "$policy_stub"
quattro_policy_source=$(sed -n '/^verify_effective_omarchy_package_policy() {/,/^}/p' "$upgrade" |
  sed "s#/usr/bin/pacman-conf#$policy_stub#g")

for implementation in quattro; do
  source_var="${implementation}_policy_source"
  source_text=${!source_var}
  (
    fail() { return 97; }
    eval "$source_text"
    TEST_POLICY='PackageRequired DatabaseOptional PackageTrustedOnly DatabaseTrustedOnly' \
      verify_effective_omarchy_package_policy
  ) || fail "$implementation rejects the secure effective package policy"

  (
    fail() { return 97; }
    eval "$source_text"
    TEST_REPO_POLICY='' \
      TEST_GLOBAL_POLICY='PackageRequired DatabaseOptional PackageTrustedOnly DatabaseTrustedOnly' \
      verify_effective_omarchy_package_policy
  ) || fail "$implementation rejects a secure inherited global package policy"

  for unsafe_policy in \
    'PackageOptional DatabaseOptional PackageTrustedOnly DatabaseTrustedOnly' \
    'PackageRequired DatabaseOptional PackageTrustAll DatabaseTrustedOnly' \
    'PackageRequired PackageOptional PackageTrustedOnly' \
    ''; do
    if (
      fail() { return 97; }
      eval "$source_text"
      TEST_POLICY="$unsafe_policy" verify_effective_omarchy_package_policy
    ) >/dev/null 2>&1; then
      fail "$implementation accepts unsafe or ambiguous effective policy '$unsafe_policy'"
    fi
  done
  if (
    fail() { return 97; }
    eval "$source_text"
    TEST_REPO_POLICY='PackageOptional DatabaseOptional PackageTrustedOnly DatabaseTrustedOnly' \
      TEST_GLOBAL_POLICY='PackageRequired DatabaseOptional PackageTrustedOnly DatabaseTrustedOnly' \
      verify_effective_omarchy_package_policy
  ) >/dev/null 2>&1; then
    fail "$implementation ignores an unsafe repository override"
  fi
  if (
    fail() { return 97; }
    eval "$source_text"
    TEST_POLICY_STATUS=9 verify_effective_omarchy_package_policy
  ) >/dev/null 2>&1; then
    fail "$implementation accepts an unreadable effective policy"
  fi
done
pass "effective pacman policy is resolved and enforced before the Quattro package transaction"

# pacman-conf returns an empty repo-level SigLevel when a repository inherits
# the global policy. Exercise the production parser against real pacman-conf so
# the test cannot teach a stub-only interpretation of that output.
real_inherited_config="$test_tmp/pacman-inherited.conf"
cat >"$real_inherited_config" <<'CONF'
[options]
SigLevel = Required DatabaseOptional
[omarchy]
Server = file:///tmp/omarchy-security-test
CONF
real_unsafe_override_config="$test_tmp/pacman-unsafe-override.conf"
cat >"$real_unsafe_override_config" <<'CONF'
[options]
SigLevel = Required DatabaseOptional
[omarchy]
Server = file:///tmp/omarchy-security-test
SigLevel = PackageOptional
CONF
for implementation in quattro; do
  source_var="${implementation}_policy_source"
  source_text=${!source_var}
  source_text=${source_text//$policy_stub//usr/bin/pacman-conf --config \"\$REAL_POLICY_CONFIG\"}
  (
    fail() { return 97; }
    eval "$source_text"
    REAL_POLICY_CONFIG="$real_inherited_config" verify_effective_omarchy_package_policy
  ) || fail "$implementation rejects Pacman's real inherited secure policy"
  if (
    fail() { return 97; }
    eval "$source_text"
    REAL_POLICY_CONFIG="$real_unsafe_override_config" verify_effective_omarchy_package_policy
  ) >/dev/null 2>&1; then
    fail "$implementation accepts Pacman's real unsafe repository override"
  fi
done
pass "real pacman-conf inheritance and repository overrides are interpreted correctly"

# A minimal unsigned local package under the final policy must be rejected by
# real pacman. DatabaseOptional permits the unsigned database, never a package.
if command -v repo-add >/dev/null && command -v bsdtar >/dev/null && command -v zstd >/dev/null &&
  unshare --user --map-root-user true 2>/dev/null; then
  repo="$test_tmp/repo"
  root="$test_tmp/pacman-root"
  mkdir -p "$repo/pkg" "$root/var/lib/pacman" "$root/var/cache/pacman/pkg" "$root/etc/pacman.d/gnupg"
  cat >"$repo/pkg/.PKGINFO" <<'PKG'
pkgname = omarchy-audit-unsigned
pkgver = 1-1
pkgdesc = isolated unsigned audit fixture
builddate = 1
packager = Omarchy test
size = 0
arch = any
PKG
  bsdtar -C "$repo/pkg" -cf - .PKGINFO | zstd -q -o "$repo/omarchy-audit-unsigned-1-1-any.pkg.tar.zst"
  repo-add -q "$repo/omarchy.db.tar.gz" "$repo/omarchy-audit-unsigned-1-1-any.pkg.tar.zst"
  cat >"$test_tmp/pacman-test.conf" <<CONF
[options]
Architecture = auto
SigLevel = Required DatabaseOptional
[omarchy]
SigLevel = Required DatabaseOptional
Server = file://$repo
CONF
  if ! unshare --user --map-root-user bash -euo pipefail -c '
    pacman --config "$1" --root "$2" --dbpath "$2/var/lib/pacman" \
      --cachedir "$2/var/cache/pacman/pkg" -Sy --noconfirm >/dev/null
    if pacman --config "$1" --root "$2" --dbpath "$2/var/lib/pacman" \
      --cachedir "$2/var/cache/pacman/pkg" -S --noconfirm omarchy-audit-unsigned >"$3" 2>&1; then
      exit 90
    fi
  ' _ "$test_tmp/pacman-test.conf" "$root" "$test_tmp/pacman.out"; then
    fail "isolated pacman did not enforce the final signature policy" "$(cat "$test_tmp/pacman.out" 2>/dev/null || true)"
  fi
  [[ ! -e $root/usr ]] || fail "unsigned package modified isolated pacman root"
  pass "real pacman rejects unsigned packages under final Omarchy policy"
else
  pass "package construction tools unavailable; static signature-policy checks completed"
fi
