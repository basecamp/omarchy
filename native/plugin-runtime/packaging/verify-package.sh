#!/bin/bash

set -euo pipefail

if (( $# != 1 )); then
  echo "Usage: $0 <omarchy-package.pkg.tar.zst>" >&2
  exit 64
fi

package=$1
[[ -f $package ]] || { echo "Package not found: $package" >&2; exit 66; }

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

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
staging=$(mktemp -d)
cleanup() {
  rm -rf -- "$staging"
}
trap cleanup EXIT

bsdtar -xf "$package" -C "$staging"
bsdtar -xOf "$package" .PKGINFO >"$staging/.PKGINFO"

host=$staging/usr/bin/omarchy-plugin-host
worker=$staging/usr/lib/omarchy/plugin-runtime/omarchy-plugin-qml-worker
module=$staging/usr/lib/qt6/qml/Omarchy/PluginHost

require_mode "$host" 755 "trusted host"
require_mode "$worker" 755 "private worker"
[[ ! -e $staging/usr/bin/omarchy-plugin-qml-worker ]] ||
  fail "worker is exposed through /usr/bin"
require_mode "$staging/usr/bin/omarchy-plugin-permission-store" 755 \
  "permission store CLI"
require_mode "$staging/usr/bin/omarchy-plugin-audit-store" 755 \
  "audit store CLI"
require_mode "$staging/usr/lib/systemd/user/omarchy-plugin-host.service" 644 \
  "plugin host user service"
require_mode "$module/qmldir" 644 "QML module descriptor"
require_mode "$module/omarchy-plugin-host-bridge.qmltypes" 644 \
  "QML type description"
require_mode "$module/libomarchy-plugin-host-bridge.so" 755 \
  "QML bridge plugin"

grep -Fx 'arch = x86_64' "$staging/.PKGINFO" >/dev/null ||
  fail "native runtime package is not x86_64"
for dependency in bubblewrap libseccomp qt6-base qt6-declarative; do
  grep -Fx "depend = $dependency" "$staging/.PKGINFO" >/dev/null ||
    fail "package metadata omits runtime dependency $dependency"
done

service=$staging/usr/lib/systemd/user/omarchy-plugin-host.service
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
(( worker_status == 78 ))

if readelf -d "$host" "$worker" "$module/libomarchy-plugin-host-bridge.so" |
    grep -Eq '\((RPATH|RUNPATH)\)'; then
  fail "packaged runtime contains an RPATH or RUNPATH"
fi

QT_QPA_PLATFORM=offscreen \
  QT_QPA_PLATFORMTHEME=none \
  QSG_RHI_BACKEND=software \
  /usr/lib/qt6/bin/qml -I "$staging/usr/lib/qt6/qml" \
  "$script_dir/ModuleProbe.qml" >/dev/null

echo "plugin package verification passed: $package"
