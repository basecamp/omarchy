#!/bin/bash

set -euo pipefail

usage() {
  echo "Usage: $0 <package-archive>" >&2
  exit 64
}

fail() {
  echo "secure plugin package lifecycle test failed: $1" >&2
  exit 1
}

if (( $# != 1 )); then
  usage
fi
if (( EUID != 0 )); then
  echo "package lifecycle testing requires root for an isolated pacman root" >&2
  exit 77
fi

archive=$(realpath -e -- "$1")
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
verifier=$(realpath -e -- "$script_dir/../verify-package.sh")
negative_verifier=$(realpath -e -- "$script_dir/../verify-package-test.sh")
runtime_source=$(realpath -e -- "$script_dir/../..")
version=0.1.0
scratch=$(mktemp -d)
cleanup() {
  rm -rf -- "$scratch"
}
trap cleanup EXIT

verify_root=$scratch/verified-payload
install -d -m 755 "$verify_root"
bsdtar --numeric-owner -xpf "$archive" -C "$verify_root" \
  --exclude .BUILDINFO --exclude .MTREE --exclude .PKGINFO
"$verifier" --staging "$verify_root" "$version"
"$script_dir/verify-archive-metadata.sh" "$archive" "$version"

cmake -S "$runtime_source" -B "$scratch/verifier-config" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DBUILD_TESTING=OFF
"$negative_verifier" "$verify_root" "$version" "$scratch/verifier-config"

lifecycle_root=$scratch/pacman-root
install -d -m 755 \
  "$lifecycle_root/var/lib/pacman" \
  "$lifecycle_root/var/cache/pacman/pkg" \
  "$lifecycle_root/var/log" \
  "$lifecycle_root/etc/pacman.d/hooks" \
  "$lifecycle_root/usr/share/omarchy/shell/plugins/v1-example" \
  "$lifecycle_root/usr/lib/omarchy/unrelated" \
  "$lifecycle_root/home/example/.config/omarchy/plugins/v1-example"
printf 'system v1 sentinel\n' >"$lifecycle_root/usr/share/omarchy/shell/plugins/v1-example/Plugin.qml"
printf 'user v1 sentinel\n' >"$lifecycle_root/home/example/.config/omarchy/plugins/v1-example/Plugin.qml"
printf 'unrelated sentinel\n' >"$lifecycle_root/usr/lib/omarchy/unrelated/data"

inventory() {
  local root=$1
  find -P "$root" -printf '%P|%y|%m|%U|%G|%s\n' | LC_ALL=C sort
  find -P "$root" -type f -exec sha256sum {} + | \
    sed "s#  $root/#  #" | LC_ALL=C sort
}

before_system_v1=$(inventory "$lifecycle_root/usr/share/omarchy")
before_user_v1=$(inventory "$lifecycle_root/home/example/.config/omarchy")
before_unrelated=$(inventory "$lifecycle_root/usr/lib/omarchy/unrelated")

pacman_args=(
  --root "$lifecycle_root"
  --dbpath "$lifecycle_root/var/lib/pacman"
  --cachedir "$lifecycle_root/var/cache/pacman/pkg"
  --logfile "$lifecycle_root/var/log/pacman.log"
  --hookdir "$lifecycle_root/etc/pacman.d/hooks"
  --noconfirm
)
# The disposable database intentionally contains none of the host dependency
# packages, so pacman's double --nodeps form skips both dependency checks.
pacman "${pacman_args[@]}" --nodeps --nodeps --noscriptlet -U "$archive"

integrity=$(pacman "${pacman_args[@]}" -Qkk omarchy-plugin-security)
[[ $integrity == *"0 altered files"* ]] ||
  fail "pacman found package files that differ from .MTREE"

[[ $(inventory "$lifecycle_root/usr/share/omarchy") == "$before_system_v1" ]] ||
  fail "installation changed the system v1 plugin tree"
[[ $(inventory "$lifecycle_root/home/example/.config/omarchy") == "$before_user_v1" ]] ||
  fail "installation changed the user v1 plugin tree"
[[ $(inventory "$lifecycle_root/usr/lib/omarchy/unrelated") == "$before_unrelated" ]] ||
  fail "installation changed unrelated Omarchy files"
[[ -d $lifecycle_root/usr/lib/omarchy/plugin-security/$version/capabilities.d ]] ||
  fail "installation omitted capabilities.d"

pacman "${pacman_args[@]}" --nodeps --nodeps --noscriptlet -R omarchy-plugin-security

[[ ! -e $lifecycle_root/usr/lib/omarchy/plugin-security ]] ||
  fail "package removal left plugin-security files behind"
[[ $(inventory "$lifecycle_root/usr/share/omarchy") == "$before_system_v1" ]] ||
  fail "removal changed the system v1 plugin tree"
[[ $(inventory "$lifecycle_root/home/example/.config/omarchy") == "$before_user_v1" ]] ||
  fail "removal changed the user v1 plugin tree"
[[ $(inventory "$lifecycle_root/usr/lib/omarchy/unrelated") == "$before_unrelated" ]] ||
  fail "removal changed unrelated Omarchy files"

echo "secure plugin package install/removal lifecycle passed: $archive"
