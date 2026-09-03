#!/bin/bash

set -euo pipefail

qml_root=$1
expected='FileView FileViewError StdioCollector'
actual=$(awk '$1 == "singleton" { print $2 } $1 !~ /^(module|singleton)$/ && NF >= 2 { print $1 }' "$qml_root/qmldir" | sort | xargs)
[[ $actual == "$expected" ]] || {
  echo "unexpected Quickshell.Io compatibility API: $actual" >&2
  exit 1
}

! rg -n '\bProcess\b|\binvoke\b|\bsocket\b|\bconnect\b|shell/Commons|shell/Ui|Hyprland|DBus' "$qml_root" >/dev/null || {
  echo "Quickshell.Io compatibility module contains forbidden authority" >&2
  exit 1
}

rg -q 'runtime\.readPackagedText' "$qml_root/FileView.qml"
rg -q 'file:///plugin/' "$qml_root/FileView.qml"
rg -q 'FileViewError\.PermissionDenied' "$qml_root/FileView.qml"
