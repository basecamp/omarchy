#!/bin/bash

set -euo pipefail

spike_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
build_dir=${1:-"$spike_dir/build"}
mkdir -p "$build_dir"
build_dir=$(cd "$build_dir" && pwd)
install_dir="$build_dir/install"
qml_import_root="$install_dir/lib/qt6/qml"

cmake \
  -S "$spike_dir" \
  -B "$build_dir" \
  -G Ninja \
  -DCMAKE_BUILD_TYPE=None \
  -DCMAKE_INSTALL_PREFIX="$install_dir"
cmake --build "$build_dir"
ctest --test-dir "$build_dir" --output-on-failure
cmake --install "$build_dir"

QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=none QT_QUICK_BACKEND=software \
  "$install_dir/bin/omarchy-plugin-host-smoke" "$qml_import_root"
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=none QT_QUICK_BACKEND=software \
  "$install_dir/bin/omarchy-plugin-frame-smoke" "$qml_import_root"

if [[ ${2:-} == "--quickshell" ]]; then
  runtime_dir=$(mktemp -d /tmp/omarchy-plugin-host-runtime.XXXXXX)
  trap 'rm -rf -- "$runtime_dir"' EXIT
  state_dir="$build_dir/quickshell-state"
  cache_dir="$build_dir/quickshell-cache"
  data_dir="$build_dir/quickshell-data"
  config_dir="$build_dir/quickshell-config"
  mkdir -p "$state_dir" "$cache_dir" "$data_dir" "$config_dir"
  chmod 700 "$runtime_dir"

  set +e
  quickshell_output=$(env -u WAYLAND_DISPLAY -u DISPLAY \
    QML_IMPORT_PATH="$qml_import_root" \
    XDG_RUNTIME_DIR="$runtime_dir" \
    XDG_STATE_HOME="$state_dir" \
    XDG_CACHE_HOME="$cache_dir" \
    XDG_DATA_HOME="$data_dir" \
    XDG_CONFIG_HOME="$config_dir" \
    QT_QPA_PLATFORM=offscreen \
    QT_QPA_PLATFORMTHEME=none \
    QT_QUICK_BACKEND=software \
    timeout 3 quickshell --no-color -p "$spike_dir/QuickshellSmoke.qml" 2>&1)
  quickshell_status=$?
  set -e
  printf '%s\n' "$quickshell_output"

  if [[ $quickshell_output != *"host-module-quickshell-smoke: omarchy-plugin-host-loaded"* ]]; then
    echo "Quickshell did not instantiate Omarchy.PluginHost" >&2
    exit 1
  fi
  if (( quickshell_status != 0 && quickshell_status != 124 )); then
    echo "Quickshell exited unexpectedly with status $quickshell_status" >&2
    exit 1
  fi
fi
