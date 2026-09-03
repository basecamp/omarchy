#!/bin/bash

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG=/usr/share/locale/ja/LC_MESSAGES/kconfig6_qt.qm
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"

if [[ ! -f $CATALOG ]]; then
  echo "Japanese Qt test catalog is unavailable: $CATALOG" >&2
  exit 77
fi

output="$(QT_QPA_PLATFORM=offscreen \
  QML_IMPORT_PATH="$BUILD_DIR/qml${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  quickshell -p "$ROOT/tests/translation-test.qml" 2>&1)" || {
    status=$?
    printf '%s\n' "$output" >&2
    exit "$status"
  }

printf '%s\n' "$output"
[[ $output == *"TEST_PASS:"* ]]
