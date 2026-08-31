#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(`${root}/shell/plugins/lock/Service.qml`, 'utf8')
const viewQml = fs.readFileSync(`${root}/shell/plugins/lock/LockView.qml`, 'utf8')

assert(
  /Variants \{\s*model: Quickshell\.screens[\s\S]*Image \{[\s\S]*visible: false[\s\S]*source: root\.backgroundFileUrl\(root\.backgroundPath\)/.test(serviceQml),
  'the lock service preloads one hidden wallpaper image per output'
)

assert(
  /sourceSize\.width: Math\.max\(1, modelData\.width\)[\s\S]*sourceSize\.height: Math\.max\(1, modelData\.height\)/.test(serviceQml),
  'preloaded wallpapers match each output size'
)

assert(
  /source: root\.loadBackground \? root\.fileUrl\(root\.backgroundPath\) : ""[\s\S]*asynchronous: false[\s\S]*cache: true/.test(viewQml),
  'lock surfaces synchronously reuse the preloaded cache entry'
)

assert(
  /function backgroundFileUrl\(path\)[\s\S]*"file:\/\/" \+ encoded \+ "\?v=" \+ backgroundVersion/.test(serviceQml),
  'the preloader uses the same cache-busted URL as LockView'
)
JS
