#!/bin/bash
source "$(dirname "$0")/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')

const backgroundQml = fs.readFileSync(path.join(root, 'shell/plugins/background/Background.qml'), 'utf8')

// Extract one block by taking everything from the marker to the line whose
// closing brace sits at the block's own indentation: a `function ...` marker
// opens its brace on the marker line, while an `id: ...` marker is the first
// line inside a brace opened two spaces shallower. Keeps the assertions
// below tolerant of formatting inside the block.
function blockAfter(source, marker, description) {
  const start = source.indexOf(marker)
  if (start < 0) fail(description, `marker not found: ${marker}`)
  const indent = source.slice(source.lastIndexOf('\n', start) + 1, start)
  const closerIndent = marker.startsWith('function') ? indent : indent.slice(0, -2)
  const rest = source.slice(start)
  const end = rest.indexOf('\n' + closerIndent + '}')
  if (end < 0) fail(description, `unterminated block for marker: ${marker}`)
  pass(description)
  return rest.slice(0, end)
}

assert(
  /theme=\$\(omarchy-theme-switcher\); \[\[ -n \$theme \]\] && omarchy-theme-set \\"\$theme\\" >\/dev\/null 2>&1 &/.test(backgroundQml),
  'background theme switcher starts theme application asynchronously after selection'
)

assert(
  backgroundQml.includes('pendingThemeFallbackTimer.restart()') &&
    backgroundQml.includes('pendingThemeFallbackTimer.stop()') &&
    backgroundQml.includes('id: pendingThemeFallbackTimer') &&
    !backgroundQml.includes('pendingThemeVersion !== backgroundVersion'),
  'background theme transition applies pending colors even if image reveal stalls'
)

assert(
  (backgroundQml.match(/BackgroundResolver\s*\{/g) || []).length === 3,
  'each background panel resolves displayed, old, and incoming layers with its own resolvers'
)

const displayedResolver = blockAfter(backgroundQml, 'id: displayedResolver', 'displayed resolver block exists')
const oldResolver = blockAfter(backgroundQml, 'id: oldResolver', 'old resolver block exists')
const incomingResolver = blockAfter(backgroundQml, 'id: incomingResolver', 'incoming resolver block exists')

assert(
  /canonicalPath:\s*root\.displayedBackground\b/.test(displayedResolver) &&
    /canonicalPath:\s*root\.oldBackground\b/.test(oldResolver),
  'displayed and old resolvers key on the root canonical paths'
)

assert(
  /canonicalPath:\s*root\.currentBackground\s*!==\s*""\s*\?\s*root\.currentBackground\s*:\s*root\.incomingBackground/.test(incomingResolver),
  'incoming layer resolves against the final canonical, not the transition snapshot'
)

assert(
  (backgroundQml.match(/screenWidth:\s*panel\.modelData\.width/g) || []).length === 3 &&
    (backgroundQml.match(/screenHeight:\s*panel\.modelData\.height/g) || []).length === 3,
  'every resolver uses its own panel screen dimensions'
)

assert(
  /refreshToken:\s*root\.backgroundVersion/.test(oldResolver) &&
    /refreshToken:\s*root\.backgroundVersion/.test(incomingResolver) &&
    /refreshToken:\s*root\.displayedVersion/.test(displayedResolver),
  'a forced transition with an unchanged canonical path still re-resolves all three layers'
)

assert(
  (backgroundQml.match(/displayedVersion\s*\+=\s*1/g) || []).length >= 2,
  'displayed re-resolution is requested on every displayedBackground assignment (instant set and reveal end)'
)

const baseBlock = blockAfter(backgroundQml, 'id: base', 'base layer block exists')
const oldFrameBlock = blockAfter(backgroundQml, 'id: oldFrame', 'old frame block exists')
const incomingFrameBlock = blockAfter(backgroundQml, 'id: incomingFrame', 'incoming frame block exists')

assert(
  /^\s*WallpaperImage\s*\{\s*$/m.test(backgroundQml) &&
    baseBlock.startsWith('id: base') &&
    oldFrameBlock.startsWith('id: oldFrame') &&
    incomingFrameBlock.startsWith('id: incomingFrame') &&
    !/\bImage\s*\{/.test(backgroundQml),
  'all three background layers render through WallpaperImage'
)

// Per-panel incoming source lock: pixels/meta commit exactly once per
// transition, from the resolver when it lands in time or from the snapshot
// after the fallback timer, and never swap mid-reveal.
const lockBlock = blockAfter(backgroundQml, 'function lockIncoming', 'incoming lock function exists')
assert(
  /if\s*\(incomingLockedVersion\s*===\s*root\.backgroundVersion\)\s*return/.test(lockBlock) &&
    /incomingLockedVersion\s*=\s*root\.backgroundVersion/.test(lockBlock),
  'a panel locks its incoming source at most once per backgroundVersion'
)

assert(
  /path:\s*panel\.incomingPath\b/.test(incomingFrameBlock) &&
    /fill:\s*panel\.incomingFill\b/.test(incomingFrameBlock),
  'incoming pixels and meta come from the per-panel lock, not live resolver bindings'
)

assert(
  /usedFallback\s*\?\s*root\.incomingBackground\s*:\s*resolvedPath/.test(incomingResolver),
  'a failed incoming resolve falls back to the handed-down snapshot pixels'
)

const fallbackTimer = blockAfter(backgroundQml, 'id: incomingFallbackTimer', 'incoming fallback timer exists')
assert(
  /interval:\s*250\b/.test(fallbackTimer) &&
    /lockIncoming\(root\.incomingBackground,\s*panel\.lastDisplayedFill/.test(fallbackTimer),
  'a slow incoming resolve times out to the snapshot with the panel cached displayed meta'
)

assert(
  /incomingFallbackTimer\.restart\(\)/.test(backgroundQml) &&
    /incomingLockedVersion\s*=\s*-1/.test(backgroundQml),
  'arming a transition resets the per-panel lock and starts the snapshot timeout'
)

// Join tolerance: a panel whose incoming frame lands mid-animation still
// raises its mask instead of being excluded for the rest of the reveal.
const maybeStart = blockAfter(backgroundQml, 'function maybeStartReveal', 'maybeStartReveal exists')
assert(
  /root\.revealProgress\s*>=\s*1/.test(maybeStart) &&
    !/revealProgress\s*!==\s*0/.test(maybeStart),
  'a panel becoming ready mid-animation still joins the reveal at the current mask spread'
)

// Source continuity: the shared incoming/old sources are only cleared once
// every panel base has settled on the final background.
const finishBlock = blockAfter(backgroundQml, 'function maybeFinishTransition', 'maybeFinishTransition exists')
assert(
  /panelVariants\.instances/.test(finishBlock) &&
    /baseSettled\(\)/.test(finishBlock) &&
    /incomingBackground\s*=\s*""/.test(finishBlock) &&
    /oldBackground\s*=\s*""/.test(finishBlock),
  'the global transition clear waits for every panel base to settle'
)

assert(
  /onStatusChanged:\s*root\.maybeFinishTransition\(\)/.test(baseBlock) &&
    /root\.maybeFinishTransition\(\)/.test(displayedResolver) &&
    !/root\.incomingBackground\s*=\s*""/.test(baseBlock),
  'no single panel base clears the shared sources on its own'
)

const settledBlock = blockAfter(backgroundQml, 'function baseSettled', 'baseSettled exists')
assert(
  /displayedResolver\.ready/.test(settledBlock) &&
    /lastDisplayedCanonical\s*!==\s*root\.displayedBackground/.test(settledBlock) &&
    /base\.status\s*!==\s*Image\.Loading/.test(settledBlock),
  'a panel settles only once its own resolve published for the final canonical and the decode is done'
)

const resolverQml = fs.readFileSync(path.join(root, 'shell/Ui/BackgroundResolver.qml'), 'utf8')

assert(
  /"omarchy-theme-bg-resolve",\s+"--screen",\s*screenWidth\s*\+\s*"x"\s*\+\s*screenHeight,\s+"--canonical",\s*canonicalPath/.test(resolverQml),
  'background resolver asks omarchy-theme-bg-resolve for the per-screen resolution'
)

assert(
  /property int refreshToken/.test(resolverQml) &&
    /onRefreshTokenChanged:\s*requestResolve\(\)/.test(resolverQml),
  'resolvers re-resolve when their refresh token bumps even if inputs are string-identical'
)

const requestBlock = blockAfter(resolverQml, 'function requestResolve', 'requestResolve exists')
const startBlock = blockAfter(resolverQml, 'function startResolve', 'startResolve exists')
const invalidGuard = /if\s*\(!canonicalPath\s*\|\|\s*screenWidth\s*<=\s*0\s*\|\|\s*screenHeight\s*<=\s*0\)/

assert(
  invalidGuard.test(requestBlock) &&
    /resolvePending\s*=\s*false[\s\S]*publishFallback\(requestSeq\)/.test(requestBlock),
  'invalid resolver inputs clear any queued relaunch before publishing the fallback'
)

assert(
  invalidGuard.test(startBlock) &&
    /publishFallback\(requestSeq\)/.test(startBlock),
  'a relaunch re-validates inputs instead of spawning a resolve with an empty canonical'
)

const wallpaperQml = fs.readFileSync(path.join(root, 'shell/Ui/WallpaperImage.qml'), 'utf8')

assert(
  wallpaperQml.includes('return Image.PreserveAspectCrop') &&
    /property string fill:\s*"crop"/.test(wallpaperQml),
  'wallpaper image defaults to the historical centered crop rendering'
)

assert(
  /capActive:\s*root\.useSourceSizeCap\s*&&\s*root\.fill\s*!==\s*"center"\s*&&\s*root\.fill\s*!==\s*"tile"/.test(wallpaperQml),
  'the source-size cap never applies to center or tile, which paint at natural size'
)

const sourceSizeWidth = (wallpaperQml.match(/sourceSize\.width:\s*\{[\s\S]*?\n\s*\}/) || [''])[0]
assert(
  /naturalAspect\s*>\s*image\.physWidth\s*\/\s*image\.physHeight\s*\?\s*Math\.round\(image\.physHeight\s*\*\s*image\.naturalAspect\)\s*:\s*image\.physWidth/.test(wallpaperQml) &&
    /root\.manualCrop/.test(sourceSizeWidth),
  'the manual focal crop decodes at the cover dimensions instead of fit-within'
)

assert(
  /onSourceChanged:\s*naturalAspect\s*=\s*0/.test(wallpaperQml),
  'a new source relearns the natural aspect before re-deriving the cover decode size'
)
JS
