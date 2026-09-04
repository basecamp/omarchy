#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const vm = require('vm')
const selection = {}
vm.createContext(selection)
vm.runInContext(fs.readFileSync(path.join(root, 'shell/plugins/background/Wallpaper.js'), 'utf8'), selection)
const choose = (config, name = 'DP-1', w = 1920, h = 1080) => selection.select(config, name, w, h, '/home/test')
assert(choose(undefined) === '', 'no configuration preserves the theme wallpaper')
const config = {monitors: {'DP-1': '~/Pictures/main #1.jpg'}, portrait: '/portrait.jpg', landscape: '/landscape.jpg'}
assert(choose(config) === '/home/test/Pictures/main #1.jpg', 'named monitor wins and expands home without damaging special characters')
assert(choose(config, 'DP-1', 1080, 1920) === '/home/test/Pictures/main #1.jpg', 'named override survives rotation')
assert(choose(config, 'HDMI-A-1', 1080, 1920) === '/portrait.jpg', 'portrait orientation default')
assert(choose(config, 'HDMI-A-1', 1920, 1080) === '/landscape.jpg', 'rotation reevaluates orientation')
assert(choose(config, 'NEW-1', 1080, 1920) === '/portrait.jpg', 'new displays use orientation defaults')
assert(choose(config, 'NEW-1', 1000, 1000) === '/landscape.jpg', 'square displays use landscape')
assert(choose({portrait: '/portrait.jpg'}) === '', 'unconfigured orientation uses theme')
for (const invalid of [null, 42, {}, '', 'relative.jpg', 'https://example.com/a.jpg']) {
  assert(choose({monitors: {'DP-1': invalid}, landscape: '/landscape.jpg'}) === '', 'invalid named setting falls directly back to theme')
}
assert(choose({monitors: {}, landscape: '/landscape.jpg'}) === '/landscape.jpg', 'removing a named setting restores orientation default')
assert(choose({}) === '', 'removing all overrides restores theme')

const qml = fs.readFileSync(path.join(root, 'shell/plugins/background/Background.qml'), 'utf8')
const context = {
  finishingTransition: true, incomingBackground: '/incoming.jpg', oldBackground: '/old.jpg',
  panels: [{baseReady: true}, {baseReady: false}]
}
vm.createContext(context)
const finish = qml.match(/^  function finishTransition\(\) \{[\s\S]*?^  \}/m)
assert(finish, 'transition completion function exists')
vm.runInContext(finish[0], context)
context.finishTransition()
assert(context.finishingTransition && context.incomingBackground, 'slow display keeps transition layers alive')
context.panels[1].baseReady = true
context.finishTransition()
assert(!context.finishingTransition && context.incomingBackground === '' && context.oldBackground === '', 'already-loaded overrides finish without a new status event')
context.finishingTransition = true
context.panels = []
context.finishTransition()
assert(!context.finishingTransition, 'disconnecting all displays cannot strand cleanup')

const transitions = {
  currentBackground: '/old.jpg', displayedBackground: '/old.jpg', incomingBackground: '', oldBackground: '',
  backgroundVersion: 0, revealStartedVersion: -1, pendingThemeVersion: -1, revealProgress: 1,
  pendingColorsRaw: '', pendingShellRaw: '', finishingTransition: false, starts: 0, colorsApplied: 0,
  Util: {decodeBase64: value => value}, Style: {scheduleRefresh() {}},
  pendingThemeFallbackTimer: {restart() {}, stop() {}}
}
transitions.revealAnimation = {stop() {}, restart() {transitions.starts++}}
transitions.Color = {loadColors() {transitions.colorsApplied++}, loadShell() {}}
vm.createContext(transitions)
for (const name of ['transitionBackground', 'setPendingTheme', 'applyPendingTheme', 'transitionBackgroundWithTheme', 'startReveal']) {
  const fn = qml.match(new RegExp('^  function ' + name + '\\([^]*?^  \\}', 'm'))
  assert(fn, name + ' exists')
  vm.runInContext(fn[0], transitions)
}
transitions.transitionBackgroundWithTheme('/old.jpg', '/staged.jpg', '/final.jpg', 'colors', 'shell')
assert(transitions.incomingBackground === '/staged.jpg' && transitions.oldBackground === '/old.jpg', 'theme transition keeps outgoing and staged incoming images distinct')
assert(transitions.currentBackground === '/final.jpg' && transitions.revealProgress === 0, 'theme transition retains final image and resets reveal')
const first = {maskReady: false}, second = {maskReady: false}
transitions.startReveal(first)
transitions.startReveal(second)
assert(first.maskReady && second.maskReady && transitions.starts === 1, 'already-ready and late-ready monitors share one animation')
assert(transitions.colorsApplied === 1 && transitions.pendingThemeVersion === -1, 'fixed wallpapers still apply pending theme colors once')
transitions.transitionBackground('', '/cycled.jpg', '/cycled.jpg', false, false)
assert(transitions.incomingBackground === '/cycled.jpg' && transitions.revealStartedVersion === -1, 'cycling resets reveal state for the next image')
transitions.startReveal(first)
assert(transitions.starts === 2, 'successive wallpaper changes each start a reveal')
transitions.transitionBackground('', '/instant.jpg', '/instant.jpg', true, false)
assert(transitions.displayedBackground === '/instant.jpg' && transitions.incomingBackground === '' && transitions.revealProgress === 1, 'instant initialization leaves no transition layers')

JS

qml_runner="${QMLTESTRUNNER:-$(command -v qmltestrunner || true)}"
if [[ -z $qml_runner ]] && command -v qtpaths6 >/dev/null; then
  qml_runner="$(qtpaths6 --query QT_INSTALL_BINS)/qmltestrunner"
fi
if [[ ! -x $qml_runner ]]; then
  pass "Qt Quick Test unavailable; skipping image decoding tests"
  exit 0
fi
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= QT_QUICK_CONTROLS_STYLE=Basic \
  "$qml_runner" -input "$ROOT/test/qml/background"
