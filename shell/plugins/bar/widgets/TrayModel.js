function text(value) {
  return String(value || "").toLowerCase()
}

function itemNamed(item, name) {
  if (!item) return false
  return text(item.id).indexOf(name) !== -1
    || text(item.title).indexOf(name) !== -1
    || text(item.tooltipTitle).indexOf(name) !== -1
}

function entryId(entry) {
  if (typeof entry === "string") return entry
  if (entry && typeof entry === "object") {
    var id = entry.id
    if (id !== undefined && id !== null && String(id) !== "") return String(id)
  }
  return ""
}

function layoutHasWidget(layout, id) {
  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    var entries = layout && layout[sections[s]]
    if (!Array.isArray(entries)) continue
    for (var i = 0; i < entries.length; i++) {
      if (entryId(entries[i]) === id) return true
    }
  }
  return false
}

// Recolor decisions are made from an icon's pixels, not its name: Solaar asks
// for the themed "battery-full" (Yaru draws it at #333, for a light panel) and
// Steam publishes "steam_tray_mono", and neither carries anything the
// StatusNotifierItem protocol defines. Tray.qml walks the pixels, which needs a
// Canvas; these take the summary and apply the thresholds.

// A pixel counts as colored above this HSV saturation...
var SATURATED_PIXEL = 0.15
// ...and an icon counts as a flat silhouette below this share of them.
// Saturation is what separates a symbolic icon from a saturated single-hue
// logo: hue spread alone reads Battle.net and btop as monochrome.
var SILHOUETTE_MAX_COLORED = 0.15
// WCAG contrast against the bar, so recoloring stops at icons that are
// genuinely hard to read and a readable flat brand color keeps its own.
var MIN_READABLE_CONTRAST = 3.0

function channelToLinear(c) {
  return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)
}

function relativeLuminance(r, g, b) {
  return 0.2126 * channelToLinear(r) + 0.7152 * channelToLinear(g) + 0.0722 * channelToLinear(b)
}

function contrastRatio(a, b) {
  var hi = Math.max(a, b)
  var lo = Math.min(a, b)
  return (hi + 0.05) / (lo + 0.05)
}

// sample: { opaque, colored, luminance }
// Below this alpha a pixel is the transparent field around the glyph, and
// averaging it in would wash out the reading.
var ALPHA_FLOOR = 40

// data is a flat RGBA byte array, as Canvas getImageData().data hands it over.
// Returns the summary the decision below needs. Lives here rather than in QML so
// the thresholds are covered by the tests and never have to be referenced across
// the QML/JS boundary — TrayModel.saturatedPixel reads as undefined from QML,
// which silently made every comparison false and every icon a silhouette.
function samplePixels(data) {
  var opaque = 0
  var colored = 0
  var luminance = 0
  // Step whole pixels only. A trailing partial group is not a pixel, and reading
  // past it yields undefined channels: undefined <= ALPHA_FLOOR is false, so the
  // fragment would count as opaque and its missing channels would poison the
  // luminance average with NaN.
  for (var i = 0; i + 3 < data.length; i += 4) {
    if (data[i + 3] <= ALPHA_FLOOR) continue
    var r = data[i] / 255
    var g = data[i + 1] / 255
    var b = data[i + 2] / 255
    opaque++
    var mx = Math.max(r, g, b)
    var mn = Math.min(r, g, b)
    if (mx > 0 && (mx - mn) / mx > SATURATED_PIXEL) colored++
    luminance += relativeLuminance(r, g, b)
  }
  return {
    opaque: opaque,
    colored: colored,
    luminance: opaque > 0 ? luminance / opaque : 0
  }
}

function sampleIsSilhouette(sample) {
  if (!sample || !sample.opaque) return false
  return (sample.colored / sample.opaque) < SILHOUETTE_MAX_COLORED
}

function sampleNeedsRecolor(sample, backgroundLuminance) {
  if (!sampleIsSilhouette(sample)) return false
  return contrastRatio(sample.luminance, backgroundLuminance) < MIN_READABLE_CONTRAST
}

// LocalSend's item shows no state, offers only Open and Quit, and its primary
// click is a no-op, so Share > Receive is the whole surface. Hiding it by hand
// doesn't stick either: LocalSend picks a fresh tray id every launch.
function ownedByOmarchy(item, layout) {
  return itemNamed(item, "localsend")
    || (layoutHasWidget(layout, "omarchy.dropbox") && itemNamed(item, "dropbox"))
}

if (typeof module !== "undefined") {
  module.exports = {
    itemNamed: itemNamed,
    entryId: entryId,
    relativeLuminance: relativeLuminance,
    samplePixels: samplePixels,
    contrastRatio: contrastRatio,
    sampleIsSilhouette: sampleIsSilhouette,
    sampleNeedsRecolor: sampleNeedsRecolor,
    layoutHasWidget: layoutHasWidget,
    ownedByOmarchy: ownedByOmarchy
  }
}
