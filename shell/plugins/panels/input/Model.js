// Pure helpers for the Input panel, kept Qt-free for shell tests.

function layoutOptions(text) {
  var options = []
  var seen = {}
  var layout = ""
  var variant = ""

  String(text || "").split("\n").forEach(function (line) {
    var nextLayout = line.match(/^- layout: '(.*)'$/)
    if (nextLayout) {
      layout = nextLayout[1]
      variant = ""
      return
    }

    var nextVariant = line.match(/^  variant: '(.*)'$/)
    if (nextVariant) {
      variant = nextVariant[1]
      return
    }

    var description = line.match(/^  description: (.*)$/)
    if (!description || !layout || variant || seen[layout]) return
    seen[layout] = true
    options.push({
      value: layout,
      label: description[1],
      description: layout.toUpperCase()
    })
  })

  return options
}

function parseStatus(text) {
  try {
    var parsed = JSON.parse(String(text || "{}"))
    return parsed && parsed.version === 1 ? parsed : null
  } catch (error) {
    return null
  }
}

function composeLabel(value) {
  if (value === "ralt") return "Right Alt"
  if (value === "menu") return "Menu key"
  if (value === "none") return "Disabled"
  return "Caps Lock"
}

function heroMeta(config) {
  var value = String(config && config.primary || "us").toUpperCase()
  if (config && config.alternate) value += " + " + String(config.alternate).toUpperCase()
  return value + " · " + composeLabel(config && config.compose).toUpperCase() + " COMPOSE"
}

if (typeof module !== "undefined") {
  module.exports = {
    composeLabel: composeLabel,
    heroMeta: heroMeta,
    layoutOptions: layoutOptions,
    parseStatus: parseStatus
  }
}
