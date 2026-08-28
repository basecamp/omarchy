#!/bin/bash

set -euo pipefail

if (( $# != 1 )); then
  echo "Usage: $0 <omarchy-package.pkg.tar.zst>" >&2
  exit 64
fi

package=$1
[[ -f $package ]] || { echo "Package not found: $package" >&2; exit 66; }

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
staging=$(mktemp -d)
cleanup() {
  rm -rf -- "$staging"
}
trap cleanup EXIT

bsdtar -xf "$package" -C "$staging"

host=$staging/usr/bin/omarchy-plugin-host
worker=$staging/usr/lib/omarchy/plugin-runtime/omarchy-plugin-qml-worker
module=$staging/usr/lib/qt6/qml/Omarchy/PluginHost

[[ -x $host ]]
[[ -x $worker ]]
[[ ! -e $staging/usr/bin/omarchy-plugin-qml-worker ]]
[[ -x $staging/usr/bin/omarchy-plugin-permission-store ]]
[[ -x $staging/usr/bin/omarchy-plugin-audit-store ]]
[[ -r $staging/usr/lib/systemd/user/omarchy-plugin-host.service ]]
[[ -r $module/qmldir ]]
[[ -r $module/libomarchy-plugin-host-bridge.so ]]

"$host" --version | grep -Eq '^omarchy-plugin-host [^ ]+ envelope=1$'

set +e
"$worker" >/dev/null 2>&1
worker_status=$?
set -e
(( worker_status == 78 ))

if readelf -d "$host" "$worker" "$module/libomarchy-plugin-host-bridge.so" |
    grep -Eq '\((RPATH|RUNPATH)\)'; then
  echo "Packaged plugin runtime contains an RPATH or RUNPATH" >&2
  exit 1
fi

QT_QPA_PLATFORM=offscreen \
  QT_QPA_PLATFORMTHEME=none \
  QSG_RHI_BACKEND=software \
  /usr/lib/qt6/bin/qml -I "$staging/usr/lib/qt6/qml" \
  "$script_dir/ModuleProbe.qml" >/dev/null

echo "plugin package verification passed: $package"
