#!/bin/bash

set -euo pipefail

usage() {
  echo "Usage: $0 <omarchy-package.pkg.tar.zst>" >&2
  echo "       $0 --staging <extracted-package-root>" >&2
  exit 64
}

fail() {
  echo "plugin package verification failed: $1" >&2
  exit 1
}

require_mode() {
  local path=$1 expected=$2 description=$3
  [[ -f $path && ! -L $path ]] || fail "$description is absent or linked"
  [[ $(stat -c '%a' "$path") == "$expected" ]] ||
    fail "$description mode is not $expected"
}

require_directory_mode() {
  local path=$1
  [[ -d $path && ! -L $path ]] || fail "runtime directory is absent or linked: $path"
  [[ $(stat -c '%a' "$path") == "755" ]] ||
    fail "runtime directory mode is not 755: $path"
}

require_exact_children() {
  local directory=$1 description=$2
  shift 2
  local expected actual
  expected=$(printf '%s\n' "$@" | LC_ALL=C sort)
  actual=$(find "$directory" -mindepth 1 -maxdepth 1 -printf '%f\n' |
    LC_ALL=C sort)
  [[ $actual == "$expected" ]] ||
    fail "$description contains an unexpected or missing entry"
}

archive_owner() {
  local package=$1 member=$2
  bsdtar -tvf "$package" "$member" |
    awk 'NR == 1 { print $3 ":" $4 }'
}

needed_libraries() {
  readelf -d "$1" |
    sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p'
}

require_needed() {
  local elf=$1 required=$2
  needed_libraries "$elf" | grep -Fx "$required" >/dev/null ||
    fail "$(basename "$elf") omits required DT_NEEDED $required"
}

verify_elf() {
  local elf=$1 kind=$2 allowed=$3
  shift 3
  local identity needed resolution

  identity=$(file -b "$elf")
  if [[ $kind == "pie" ]]; then
    [[ $identity == *"ELF 64-bit LSB pie executable, x86-64"* ]] ||
      fail "$(basename "$elf") is not an x86-64 PIE executable"
  else
    [[ $identity == *"ELF 64-bit LSB shared object, x86-64"* ]] ||
      fail "$(basename "$elf") is not an x86-64 shared object"
  fi

  readelf -W -l "$elf" | grep -Eq 'GNU_STACK.*RW[[:space:]]' ||
    fail "$(basename "$elf") has no non-executable GNU stack declaration"
  readelf -W -l "$elf" | grep -q 'GNU_RELRO' ||
    fail "$(basename "$elf") has no GNU RELRO segment"
  if readelf -d "$elf" | grep -Eq '\((RPATH|RUNPATH)\)'; then
    fail "$(basename "$elf") contains an RPATH or RUNPATH"
  fi

  while IFS= read -r needed; do
    [[ $needed =~ $allowed ]] ||
      fail "$(basename "$elf") has unexpected DT_NEEDED $needed"
  done < <(needed_libraries "$elf")
  for needed in "$@"; do
    require_needed "$elf" "$needed"
  done

  if ! resolution=$(ldd -r "$elf" 2>&1); then
    fail "$(basename "$elf") dependency resolution failed"
  fi
  if grep -Eq 'not found|undefined symbol' <<<"$resolution"; then
    fail "$(basename "$elf") has an unresolved runtime dependency"
  fi
}

if (( $# == 1 )); then
  package=$1
  [[ -f $package ]] || { echo "Package not found: $package" >&2; exit 66; }
  staging=$(mktemp -d)
  cleanup() {
    rm -rf -- "$staging"
  }
  trap cleanup EXIT
  bsdtar -xf "$package" -C "$staging"
elif (( $# == 2 )) && [[ $1 == "--staging" ]]; then
  package=""
  staging=$2
  [[ -d $staging ]] || fail "staging root is absent"
else
  usage
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
host=$staging/usr/bin/omarchy-plugin-host
permission_store=$staging/usr/bin/omarchy-plugin-permission-store
audit_store=$staging/usr/bin/omarchy-plugin-audit-store
runtime_dir=$staging/usr/lib/omarchy/plugin-runtime
worker=$runtime_dir/omarchy-plugin-qml-worker
module=$staging/usr/lib/qt6/qml/Omarchy/PluginHost
bridge=$module/libomarchy-plugin-host-bridge.so
service=$staging/usr/lib/systemd/user/omarchy-plugin-host.service

require_directory_mode "$runtime_dir"
require_directory_mode "$module"
require_exact_children "$runtime_dir" "private worker directory" \
  omarchy-plugin-qml-worker
require_exact_children "$module" "QML plugin directory" \
  libomarchy-plugin-host-bridge.so \
  omarchy-plugin-host-bridge.qmltypes \
  qmldir

require_mode "$host" 755 "trusted host"
require_mode "$worker" 755 "private worker"
[[ ! -e $staging/usr/bin/omarchy-plugin-qml-worker ]] ||
  fail "worker is exposed through /usr/bin"
require_mode "$permission_store" 755 "permission store CLI"
require_mode "$audit_store" 755 "audit store CLI"
require_mode "$service" 644 "plugin host user service"
require_mode "$module/qmldir" 644 "QML module descriptor"
require_mode "$module/omarchy-plugin-host-bridge.qmltypes" 644 \
  "QML type description"
require_mode "$bridge" 755 "QML bridge plugin"

for path in \
  "$host" "$permission_store" "$audit_store" "$runtime_dir" "$worker" \
  "$module" "$bridge" "$module/qmldir" \
  "$module/omarchy-plugin-host-bridge.qmltypes" "$service"; do
  mode=$(stat -c '%a' "$path")
  if [[ -L $path ]] || [[ $(stat -c '%A' "$path") == *s* ]] ||
      (( (8#$mode & 8#6022) != 0 )); then
    fail "runtime install path has unsafe type or permissions: $path"
  fi
done

grep -Fx 'arch = x86_64' "$staging/.PKGINFO" >/dev/null ||
  fail "native runtime package is not x86_64"
for dependency in bubblewrap libseccomp qt6-base qt6-declarative; do
  grep -Fx "depend = $dependency" "$staging/.PKGINFO" >/dev/null ||
    fail "package metadata omits runtime dependency $dependency"
done

if [[ -n $package ]]; then
  for member in \
    usr/bin/omarchy-plugin-host \
    usr/bin/omarchy-plugin-permission-store \
    usr/bin/omarchy-plugin-audit-store \
    usr/lib/omarchy/plugin-runtime/omarchy-plugin-qml-worker \
    usr/lib/qt6/qml/Omarchy/PluginHost/libomarchy-plugin-host-bridge.so \
    usr/lib/qt6/qml/Omarchy/PluginHost/qmldir \
    usr/lib/qt6/qml/Omarchy/PluginHost/omarchy-plugin-host-bridge.qmltypes \
    usr/lib/systemd/user/omarchy-plugin-host.service; do
    [[ $(archive_owner "$package" "$member") == "root:root" ]] ||
      fail "archive member is not owned by root:root: $member"
  done
fi

for directive in \
  'After=graphical-session.target' \
  'PartOf=graphical-session.target' \
  'ConditionEnvironment=OMARCHY_PATH' \
  'ConditionEnvironment=WAYLAND_DISPLAY' \
  'ExecStart=/usr/bin/omarchy-plugin-host' \
  'Restart=on-failure' \
  'WantedBy=graphical-session.target'; do
  grep -Fx "$directive" "$service" >/dev/null ||
    fail "plugin host service omits $directive"
done

"$host" --version | grep -Eq '^omarchy-plugin-host [^ ]+ envelope=1$'

set +e
"$worker" >/dev/null 2>&1
worker_status=$?
set -e
(( worker_status == 78 )) || fail "private worker does not reject direct execution"

standard='^(libstdc\+\+\.so\.6|libgcc_s\.so\.1|libc\.so\.6)$'
host_allowed='^(libQt6Core\.so\.6|libseccomp\.so\.2|libsystemd\.so\.0|libstdc\+\+\.so\.6|libgcc_s\.so\.1|libc\.so\.6)$'
worker_allowed='^(libQt6Quick\.so\.6|libQt6Gui\.so\.6|libQt6Qml\.so\.6|libQt6Core\.so\.6|libseccomp\.so\.2|libstdc\+\+\.so\.6|libgcc_s\.so\.1|libc\.so\.6)$'
bridge_allowed='^(libQt6Quick\.so\.6|libQt6Gui\.so\.6|libQt6Qml\.so\.6|libQt6Core\.so\.6|libstdc\+\+\.so\.6|libgcc_s\.so\.1|libc\.so\.6)$'

verify_elf "$host" pie "$host_allowed" libQt6Core.so.6 libseccomp.so.2 libsystemd.so.0
verify_elf "$worker" pie "$worker_allowed" libQt6Quick.so.6 libseccomp.so.2
verify_elf "$permission_store" pie "$standard" libstdc++.so.6 libc.so.6
verify_elf "$audit_store" pie "$standard" libstdc++.so.6 libc.so.6
verify_elf "$bridge" shared "$bridge_allowed" libQt6Quick.so.6 libQt6Qml.so.6

QT_QPA_PLATFORM=offscreen \
  QT_QPA_PLATFORMTHEME=none \
  QSG_RHI_BACKEND=software \
  /usr/lib/qt6/bin/qml -I "$staging/usr/lib/qt6/qml" \
  "$script_dir/ModuleProbe.qml" >/dev/null

echo "plugin package verification passed: ${package:-$staging}"
