#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

t2_migration="$ROOT/migrations/1788163636.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

# Exercise the provenance migration with trusted absolute command paths mapped
# to deterministic stubs. Every scenario starts with unsafe T2 policy plus an
# unrelated administrator section.
stub_bin="$test_tmp/bin"
mkdir "$stub_bin"
cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
if [[ $1 == /usr/bin/install ]]; then
  filtered=("$1")
  shift
  while (($#)); do
    case $1 in
      -o|-g) shift 2 ;;
      *) filtered+=("$1"); shift ;;
    esac
  done
  exec "${filtered[@]}"
fi
exec "$@"
STUB
cat >"$stub_bin/lspci" <<'STUB'
#!/bin/bash
exit 0
STUB
cat >"$stub_bin/pacman-conf" <<'STUB'
#!/bin/bash
if [[ " $* " == *" --repo omarchy "* ]]; then
  printf '%s\n' "${TEST_REPO_SIGLEVEL-${TEST_SIGLEVEL:-PackageRequired PackageTrustedOnly}}"
else
  printf '%s\n' "${TEST_GLOBAL_SIGLEVEL-${TEST_SIGLEVEL:-PackageRequired PackageTrustedOnly}}"
fi
STUB
cat >"$stub_bin/pacman" <<'STUB'
#!/bin/bash
case $1 in
  -Q) [[ $2 == linux-t2 ]] ;;
  -Si)
    repository=${TEST_REPOSITORY:-omarchy}
    [[ ${TEST_MISSING_PACKAGE:-} != "$2" ]] || repository=core
    printf 'Repository      : %s\n' "$repository"
    ;;
  -S)
    printf 'TRANSACTION %s\n' "$*" >>"${TEST_TRANSACTION_LOG:?}"
    exit "${TEST_TRANSACTION_STATUS:-0}"
    ;;
  *) exit 2 ;;
esac
STUB
chmod +x "$stub_bin"/*

mapped_migration_template="$test_tmp/t2-migration.template.sh"
sed -e "s#/usr/bin/pacman-conf#$stub_bin/pacman-conf#g" \
  -e "s#/usr/bin/pacman#$stub_bin/pacman#g" \
  -e "s#/usr/bin/lspci#$stub_bin/lspci#g" "$t2_migration" >"$mapped_migration_template"

run_t2_scenario() {
  local name="$1" policy="$2" repository="$3"
  local repo_policy="${4-$policy}" global_policy="${5-$policy}"
  local missing_package="${6:-}" transaction_status="${7:-0}"
  local dir="$test_tmp/$name"
  mkdir "$dir"
  cat >"$dir/pacman.conf" <<'CONF'
[options]
SigLevel = Required DatabaseOptional
[arch-mact2]
Server = https://unsafe.invalid/
SigLevel = Never
[administrator]
Server = file:///srv/admin
SigLevel = Required
[omarchy]
Server = https://pkgs.omarchy.org/
CONF
  : >"$dir/transactions"
  sed \
    -e "s|^pacman_conf=/etc/pacman.conf$|pacman_conf=$dir/pacman.conf|" \
    -e "s|^repair_marker=/var/lib/omarchy/t2-package-provenance-repaired$|repair_marker=$dir/marker|" \
    "$mapped_migration_template" >"$dir/t2-migration.sh"
  HOME="$dir" PATH="$stub_bin:$PATH" TEST_REPO_SIGLEVEL="$repo_policy" \
    TEST_GLOBAL_SIGLEVEL="$global_policy" TEST_REPOSITORY="$repository" \
    TEST_MISSING_PACKAGE="$missing_package" TEST_TRANSACTION_STATUS="$transaction_status" \
    TEST_TRANSACTION_LOG="$dir/transactions" bash "$dir/t2-migration.sh" >"$dir/output" 2>&1
}

if run_t2_scenario insecure 'PackageOptional PackageTrustAll' omarchy; then
  fail "T2 migration accepts insecure effective package policy"
fi
! grep -q '^TRANSACTION' "$test_tmp/insecure/transactions" || fail "insecure T2 policy reaches pacman transaction"
! grep -q '^\[arch-mact2\]' "$test_tmp/insecure/pacman.conf" || fail "unsafe T2 repo survives failed migration"
grep -q '^\[administrator\]' "$test_tmp/insecure/pacman.conf" || fail "administrator repo was removed"
backup=$(find "$test_tmp/insecure" -name 'arch-mact2.omarchy-disabled.*.txt' -print -quit)
[[ -n $backup && $(stat -c '%a' "$backup") == 600 ]] || fail "unsafe T2 section was not privately backed up"

if run_t2_scenario unavailable 'PackageRequired PackageTrustedOnly' core; then
  fail "T2 migration accepts unavailable signed replacements"
fi
! grep -q '^TRANSACTION' "$test_tmp/unavailable/transactions" || fail "missing T2 artifacts reach pacman transaction"

if run_t2_scenario partial 'PackageRequired PackageTrustedOnly' omarchy \
  'PackageRequired PackageTrustedOnly' 'PackageRequired PackageTrustedOnly' t2fanrd; then
  fail "T2 migration accepts a partial signed replacement set"
fi
! grep -q '^TRANSACTION' "$test_tmp/partial/transactions" || fail "partial T2 artifacts reach pacman transaction"

if run_t2_scenario reinstall-failure 'PackageRequired PackageTrustedOnly' omarchy \
  'PackageRequired PackageTrustedOnly' 'PackageRequired PackageTrustedOnly' '' 33; then
  fail "T2 migration accepts a failed authenticated reinstall"
fi
[[ ! -e $test_tmp/reinstall-failure/marker ]] || fail "failed T2 reinstall publishes a completion marker"

run_t2_scenario signed 'PackageRequired PackageTrustedOnly' omarchy
transaction=$(<"$test_tmp/signed/transactions")
[[ $transaction == *'linux-t2 linux-t2-headers apple-t2-audio-config apple-bcm-firmware t2fanrd'* ]] ||
  fail "T2 migration does not reinstall every replacement together"
[[ $transaction != *'--needed'* ]] || fail "T2 migration trusts bytes installed under SigLevel=Never"
[[ -f $test_tmp/signed/marker ]] || fail "successful authenticated T2 replacement is not recorded"
: >"$test_tmp/signed/transactions"
HOME="$test_tmp/signed" PATH="$stub_bin:$PATH" \
  TEST_REPO_SIGLEVEL='PackageRequired PackageTrustedOnly' \
  TEST_GLOBAL_SIGLEVEL='PackageRequired PackageTrustedOnly' TEST_REPOSITORY=omarchy \
  TEST_TRANSACTION_LOG="$test_tmp/signed/transactions" bash "$test_tmp/signed/t2-migration.sh" >/dev/null
[[ ! -s $test_tmp/signed/transactions ]] || fail "completed T2 repair reinstalls packages again"
run_t2_scenario inherited '' omarchy '' 'PackageRequired PackageTrustedOnly'
[[ -f $test_tmp/inherited/marker ]] || fail "T2 migration rejects a secure inherited global package policy"
pass "T2 migration disables unsafe policy first and fails closed until all signed replacements exist"

# Fresh installation cannot recreate the unsigned repository path.
! rg -n 'SigLevel[[:space:]]*=[[:space:]]*(Never|Optional)|TrustAll|arch-mact2-mirror' \
  "$ROOT/install/hardware/pacman.sh" "$ROOT/install/post-install/pacman.sh" >/dev/null ||
  fail "fresh installer retains unauthenticated T2 repository configuration"
grep -F '/usr/bin/pacman-conf --repo omarchy SigLevel' "$ROOT/install/hardware/apple/fix-t2.sh" >/dev/null
pass "fresh T2 setup independently requires Omarchy's trusted-only package policy"

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
