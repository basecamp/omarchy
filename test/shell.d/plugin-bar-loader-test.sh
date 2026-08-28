#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const shellSource = fs.readFileSync(root + '/shell/shell.qml', 'utf8')
const barSource = fs.readFileSync(root + '/shell/plugins/bar/Bar.qml', 'utf8')

const loader = shellSource.slice(
  shellSource.indexOf('function loadPluginBar()'),
  shellSource.indexOf('onActiveBarSourceUrlChanged:')
)
const finalize = loader.slice(loader.indexOf('function finalize()'))
const createObjectCall = finalize.slice(
  finalize.indexOf('comp.createObject('),
  finalize.indexOf('\n      })') + '\n      })'.length
)

// #8007: a cloned/third-party bar loaded through Qt.createComponent().createObject()
// must receive every one of Bar.qml's required properties in the initial-properties
// object passed to createObject, not assigned afterwards — QML enforces required
// properties at construction, so anything injected post-construction (the way the old
// Loader.source-based pluginBarLoader worked) throws before the bar ever renders.
//
// Only the root Item's own required properties matter here — Bar.qml also declares
// `required property` inside nested delegates (Instantiator/Repeater models), which
// are satisfied by their own model data, not by createObject's initial properties.
const barRoot = barSource.slice(0, barSource.indexOf('required property var modelData'))
for (const requiredProp of Array.from(barRoot.matchAll(/required property (?:string|var) (\w+)/g)).map(m => m[1])) {
  assert(
    new RegExp(`\\b${requiredProp}\\s*:`).test(createObjectCall),
    `loadPluginBar's createObject call initializes Bar.qml's required property "${requiredProp}"`
  )
}

// Every property handed to createObject must be a live Qt.binding, not a one-time
// value snapshot — a plain value would desync from shell state the instant something
// changes after construction (the "must double-click to render" regression), whereas
// defaultBarComponent's inline `barConfig: shell.barConfig` binding stays live for the
// object's whole lifetime for free.
for (const boundProp of ['omarchyPath', 'barWidgetRegistry', 'barConfig', 'manifest']) {
  assert(
    new RegExp(`${boundProp}\\s*:\\s*Qt\\.binding\\(function\\(\\)`).test(createObjectCall),
    `loadPluginBar binds "${boundProp}" live via Qt.binding instead of a one-time value`
  )
}

// createObject's parent argument must be a real Item (pluginBarHost), not shell
// itself (a ShellRoot). Only a QQuickItem parent gives the created object a
// parentItem, which is what actually places it in the render scene graph — passing
// shell would leave the bar fully constructed but invisible until an unrelated
// relayout forced the compositor to notice it.
assert(
  /comp\.createObject\(pluginBarHost,/.test(finalize),
  'the plugin bar is parented to a real Item (pluginBarHost) so it lands in the scene graph'
)
assert(
  /id:\s*pluginBarHost/.test(shellSource) && /Item\s*\{\s*\n\s*id:\s*pluginBarHost/.test(shellSource),
  'pluginBarHost is a QQuickItem, not the ShellRoot itself'
)

// --- fallback behavior --------------------------------------------------
//
// A load failure (bad QML) and a construction failure (createObject returns
// null) must both record failedBarId so activeBarId's `selectedBarId !==
// failedBarId` check falls back to the default bar — losing either path
// silently recreates the blank-bar failure from #8007.
assert(
  /comp\.status === Component\.Error\)[\s\S]*?shell\.failedBarId = barIdAtRequest/.test(finalize),
  'a Component.Error status records failedBarId so the shell falls back to the default bar'
)
assert(
  /if \(!inst\)[\s\S]*?shell\.failedBarId = barIdAtRequest/.test(finalize),
  'a null createObject result records failedBarId so the shell falls back to the default bar'
)
assert(
  /activeBarId: selectedBarId !== failedBarId && selectedBarAvailable \? selectedBarId : defaultBarId/.test(shellSource),
  'activeBarId actually falls back to defaultBarId once failedBarId is recorded'
)

// A stale async load (superseded by a newer config change while Qt.createComponent
// was still resolving) must be dropped rather than mistakenly finalized — closure-
// captured `url`/`comp` staleness was the root cause of the double-click-to-render bug.
assert(
  /if \(shell\.pluginBarComponentUrl !== url \|\| shell\.pluginBarComponent !== comp\) return/.test(finalize),
  'a superseded plugin bar load is dropped instead of finalized against stale state'
)

// --- reload behavior ------------------------------------------------------
//
// The loader only reacts to property changes, so every input that can make a
// different bar become active must re-invoke loadPluginBar(): the selected bar id
// changing, its resolved source url changing (e.g. after a plugin rescan), and a
// plugin reload starting or finishing.
for (const trigger of ['onActiveBarSourceUrlChanged', 'onActiveBarIdChanged', 'onPluginReloadingChanged']) {
  assert(
    new RegExp(`${trigger}:\\s*shell\\.loadPluginBar\\(\\)`).test(shellSource),
    `${trigger} re-invokes loadPluginBar so a bar change is picked up`
  )
}

// A plugin reload in progress, selecting the default bar, or having no resolvable
// source url must tear down any live plugin bar instance rather than leave a stale
// one mounted.
assert(
  /if \(shell\.pluginReloading \|\| shell\.activeBarId === shell\.defaultBarId \|\| shell\.activeBarSourceUrl === ""\) \{\s*\n\s*shell\.destroyPluginBar\(\)/.test(loader),
  'loadPluginBar tears down the plugin bar when reloading, defaulted, or sourceless'
)

// destroyPluginBar must fully release the instance: clear shell.bar if it was the
// active bar, destroy the QML object, and reset the component bookkeeping so a
// later loadPluginBar() does not mistake stale state for an up-to-date build.
const destroy = shellSource.slice(
  shellSource.indexOf('function destroyPluginBar()'),
  shellSource.indexOf('function loadPluginBar()')
)
assert(/shell\.bar = null/.test(destroy), 'destroyPluginBar clears shell.bar when it held the plugin instance')
assert(/shell\.pluginBarInstance\.destroy\(\)/.test(destroy), 'destroyPluginBar destroys the QML instance')
assert(/shell\.pluginBarComponent = null/.test(destroy), 'destroyPluginBar clears the tracked component')
assert(/shell\.pluginBarComponentUrl = ""/.test(destroy), 'destroyPluginBar clears the tracked component url')

// An already-built bar for the exact same url must be left alone rather than
// rebuilt on every reactive trigger (e.g. an unrelated shell.json field changing).
assert(
  /if \(shell\.pluginBarInstance && shell\.pluginBarComponentUrl === shell\.activeBarSourceUrl\) return/.test(loader),
  'loadPluginBar reuses an already-built instance instead of rebuilding on every trigger'
)
JS