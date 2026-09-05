// How wide omarchy-ascii draws each character, in terminal columns: the width it
// takes as the first character of a line, and the width it adds after one. Both
// are properties of Delta Corps Priest 1, which is embedded in omarchy-ascii, and
// screensaver-text-test.sh measures the renderer to check every entry against it.
//
// A character adds the same width whatever precedes it -- the font kerns, but the
// amount never depends on the left neighbour -- so a line's width is the first
// character's width plus the sum of what the rest add. Upper and lower case are
// drawn identically, so one entry serves both.
var METRICS = {
  "A": [12, 13], "B": [12, 13], "C": [10, 11], "D": [10, 11], "E": [12, 13],
  "F": [12, 13], "G": [12, 13], "H": [14, 15], "I": [4, 5], "J": [7, 8],
  "K": [11, 12], "L": [9, 10], "M": [16, 16], "N": [9, 10], "O": [10, 11],
  "P": [12, 13], "Q": [11, 12], "R": [12, 13], "S": [12, 13], "T": [11, 12],
  "U": [10, 11], "V": [10, 11], "W": [11, 12], "X": [15, 16], "Y": [9, 10],
  "Z": [11, 12], " ": [4, 5]
}

// The narrowest letter there is, which is what a space has to leave room for.
var NARROWEST = "I"

// Matched on the character itself rather than on its upper case: U+017F upper
// cases to S and U+0131 to I, and the renderer can draw neither.
function drawable(character) {
  return /^[A-Za-z ]$/.test(String(character))
}

// Trailing blanks are trimmed off the art, so a space at the end costs nothing
// until something follows it.
function columnsFor(text) {
  var body = String(text || "").replace(/ +$/, "")
  var total = 0
  var first = true

  for (var i = 0; i < body.length; i++) {
    var metric = METRICS[body[i].toUpperCase()]
    if (!metric) continue
    total += first ? metric[0] : metric[1]
    first = false
  }

  return total
}

function accepts(text, character, columns) {
  if (!drawable(character)) return false

  var current = String(text || "")

  // A space that opens the text, follows another space, or has no room for even
  // the narrowest letter after it would sit in the box invisibly -- costing
  // nothing to show, and then refusing the letter it was typed to separate.
  if (character === " ") {
    if (!current.length || current.slice(-1) === " ") return false
    return columnsFor(current + " " + NARROWEST) <= columns
  }

  return columnsFor(current + character) <= columns
}

function extended(text, character, columns) {
  var current = String(text || "")
  return accepts(current, character, columns) ? current + character : current
}

// The screensaver opens on every monitor and ttfx draws into a canvas the size of
// the terminal, so the art has to fit the narrowest one.
function fits(text, columns) {
  return columnsFor(text) <= columns
}

if (typeof module !== "undefined") {
  module.exports = {
    METRICS: METRICS,
    drawable: drawable,
    columnsFor: columnsFor,
    accepts: accepts,
    extended: extended,
    fits: fits
  }
}
