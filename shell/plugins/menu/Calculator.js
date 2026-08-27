// Arithmetic and unit conversion for the menu's search box.
//
// Every other row in the menu is looked up; this is the one that has to be
// computed from what was typed. It parses rather than evaluates: the search box
// sees whatever the user is halfway through typing, and `eval` would hand that
// the entire QML scope.

var CONSTANTS = {
  pi: Math.PI,
  e: Math.E
}

// `arity` and `maxArity` are both ends of the accepted range. A call outside it
// is not an expression -- an argument a function would ignore is a typo, and
// answering it anyway would present sqrt(4, 9) as a valid 2.
var FUNCTIONS = {
  sqrt: { arity: 1, maxArity: 1, apply: function(args) { return Math.sqrt(args[0]) } },
  abs: { arity: 1, maxArity: 1, apply: function(args) { return Math.abs(args[0]) } },
  round: {
    arity: 1,
    maxArity: 2,
    apply: function(args) {
      var factor = Math.pow(10, args.length > 1 ? Math.round(args[1]) : 0)
      return Math.round(args[0] * factor) / factor
    }
  },
  floor: { arity: 1, maxArity: 1, apply: function(args) { return Math.floor(args[0]) } },
  ceil: { arity: 1, maxArity: 1, apply: function(args) { return Math.ceil(args[0]) } },
  log: { arity: 1, maxArity: 1, apply: function(args) { return Math.log(args[0]) / Math.LN10 } },
  ln: { arity: 1, maxArity: 1, apply: function(args) { return Math.log(args[0]) } },
  min: { arity: 2, maxArity: Infinity, apply: function(args) { return Math.min.apply(null, args) } },
  max: { arity: 2, maxArity: Infinity, apply: function(args) { return Math.max.apply(null, args) } }
}

// `factor` is how much of the dimension's base unit one of this unit is worth,
// so converting is value * from.factor / to.factor. The bases are metre, gram,
// second, byte and litre. Temperature has no common zero and is converted on
// its own, below.
//
// Imperial volumes are US customary: a US pint is 473 ml, an imperial one 568.
var UNITS = {
  mm: { dimension: "length", factor: 0.001 },
  cm: { dimension: "length", factor: 0.01 },
  dm: { dimension: "length", factor: 0.1 },
  m: { dimension: "length", factor: 1 },
  km: { dimension: "length", factor: 1000 },
  in: { dimension: "length", factor: 0.0254 },
  ft: { dimension: "length", factor: 0.3048 },
  yd: { dimension: "length", factor: 0.9144 },
  mi: { dimension: "length", factor: 1609.344 },
  nmi: { dimension: "length", factor: 1852 },

  mg: { dimension: "mass", factor: 0.001 },
  g: { dimension: "mass", factor: 1 },
  kg: { dimension: "mass", factor: 1000 },
  t: { dimension: "mass", factor: 1000000 },
  oz: { dimension: "mass", factor: 28.349523125 },
  lb: { dimension: "mass", factor: 453.59237 },
  st: { dimension: "mass", factor: 6350.29318 },

  ms: { dimension: "time", factor: 0.001 },
  s: { dimension: "time", factor: 1 },
  min: { dimension: "time", factor: 60 },
  h: { dimension: "time", factor: 3600 },
  d: { dimension: "time", factor: 86400 },
  wk: { dimension: "time", factor: 604800 },

  b: { dimension: "data", factor: 1 },
  kb: { dimension: "data", factor: 1e3 },
  mb: { dimension: "data", factor: 1e6 },
  gb: { dimension: "data", factor: 1e9 },
  tb: { dimension: "data", factor: 1e12 },
  pb: { dimension: "data", factor: 1e15 },
  kib: { dimension: "data", factor: 1024 },
  mib: { dimension: "data", factor: 1048576 },
  gib: { dimension: "data", factor: 1073741824 },
  tib: { dimension: "data", factor: 1099511627776 },

  ml: { dimension: "volume", factor: 0.001 },
  cl: { dimension: "volume", factor: 0.01 },
  l: { dimension: "volume", factor: 1 },
  tsp: { dimension: "volume", factor: 0.00492892159375 },
  tbsp: { dimension: "volume", factor: 0.01478676478125 },
  floz: { dimension: "volume", factor: 0.0295735295625 },
  cup: { dimension: "volume", factor: 0.2365882365 },
  pt: { dimension: "volume", factor: 0.473176473 },
  qt: { dimension: "volume", factor: 0.946352946 },
  gal: { dimension: "volume", factor: 3.785411784 },

  c: { dimension: "temperature" },
  f: { dimension: "temperature" },
  k: { dimension: "temperature" }
}

// Only the spellings that are not the canonical symbol. Plurals are handled by
// dropping a trailing "s" at lookup time rather than listed twice here.
var ALIASES = {
  millimeter: "mm", millimetre: "mm",
  centimeter: "cm", centimetre: "cm",
  decimeter: "dm", decimetre: "dm",
  meter: "m", metre: "m",
  kilometer: "km", kilometre: "km",
  inch: "in", inches: "in",
  foot: "ft", feet: "ft",
  yard: "yd",
  mile: "mi",
  nauticalmile: "nmi",

  milligram: "mg",
  gram: "g",
  kilogram: "kg", kilo: "kg",
  tonne: "t",
  ounce: "oz",
  pound: "lb",
  stone: "st",

  millisecond: "ms", msec: "ms",
  second: "s", sec: "s",
  minute: "min",
  hour: "h", hr: "h",
  day: "d",
  week: "wk",

  byte: "b",
  kilobyte: "kb", megabyte: "mb", gigabyte: "gb", terabyte: "tb", petabyte: "pb",
  kibibyte: "kib", mebibyte: "mib", gibibyte: "gib", tebibyte: "tib",

  milliliter: "ml", millilitre: "ml",
  centiliter: "cl", centilitre: "cl",
  liter: "l", litre: "l",
  teaspoon: "tsp", tablespoon: "tbsp",
  fluidounce: "floz",
  pint: "pt", quart: "qt", gallon: "gal",

  celsius: "c", centigrade: "c",
  fahrenheit: "f",
  kelvin: "k"
}

// What a bare quantity converts into. "5km" asks a question without naming an
// answer, so each unit names the units its own readers actually want: metric
// asks for its imperial counterpart and vice versa, and the neighbouring scale
// covers the rest. Explicit lists rather than a ranking rule, because a ranking
// that picks "500000 cm" for 5 km is worse than no answer at all.
var PEERS = {
  mm: ["cm", "in"],
  cm: ["in", "mm"],
  dm: ["cm", "in"],
  m: ["ft", "cm"],
  km: ["mi", "m"],
  in: ["cm", "mm"],
  ft: ["m", "cm"],
  yd: ["m"],
  mi: ["km", "m"],
  nmi: ["km", "mi"],

  mg: ["g"],
  g: ["oz", "kg"],
  kg: ["lb", "g"],
  t: ["kg", "lb"],
  oz: ["g", "lb"],
  lb: ["kg", "g"],
  st: ["kg", "lb"],

  ms: ["s"],
  s: ["ms", "min"],
  min: ["s", "h"],
  h: ["min", "d"],
  d: ["h", "wk"],
  wk: ["d", "h"],

  b: ["kb"],
  kb: ["kib", "mb"],
  mb: ["mib", "gb"],
  gb: ["gib", "mb"],
  tb: ["tib", "gb"],
  pb: ["tb"],
  kib: ["kb", "mib"],
  mib: ["mb", "gib"],
  gib: ["gb", "mib"],
  tib: ["tb", "gib"],

  ml: ["floz", "l"],
  cl: ["ml", "floz"],
  l: ["gal", "ml"],
  tsp: ["ml"],
  tbsp: ["ml"],
  floz: ["ml", "l"],
  cup: ["ml", "l"],
  pt: ["ml", "l"],
  qt: ["l", "ml"],
  gal: ["l", "ml"],

  c: ["f", "k"],
  f: ["c", "k"],
  k: ["c", "f"]
}

// Display spellings for the units whose canonical key is not how they are
// written. Everything else prints as its key.
var SYMBOLS = {
  b: "B", kb: "kB", mb: "MB", gb: "GB", tb: "TB", pb: "PB",
  kib: "KiB", mib: "MiB", gib: "GiB", tib: "TiB",
  ml: "mL", cl: "cL", l: "L",
  c: "°C", f: "°F", k: "K"
}

function isDigit(character) {
  return character >= "0" && character <= "9"
}

function isLetter(character) {
  return (character >= "a" && character <= "z") || (character >= "A" && character <= "Z")
}

// Returns null on anything it cannot read, which is most of what a search box
// contains: the caller treats that as "this query is not a calculation".
function tokenize(text) {
  var tokens = []
  var index = 0

  while (index < text.length) {
    var character = text.charAt(index)

    if (character === " " || character === "\t") {
      index++
      continue
    }

    if (isDigit(character) || (character === "." && isDigit(text.charAt(index + 1)))) {
      var numberStart = index
      while (index < text.length && isDigit(text.charAt(index))) index++
      if (text.charAt(index) === ".") {
        index++
        while (index < text.length && isDigit(text.charAt(index))) index++
      }
      // An exponent only counts when it is complete. Half of one is the
      // constant e standing next to a number, which is not an expression, and
      // consuming it here would swallow the evidence.
      var exponent = index
      if (text.charAt(exponent) === "e" || text.charAt(exponent) === "E") {
        exponent++
        if (text.charAt(exponent) === "+" || text.charAt(exponent) === "-") exponent++
        if (isDigit(text.charAt(exponent))) {
          while (exponent < text.length && isDigit(text.charAt(exponent))) exponent++
          index = exponent
        }
      }
      tokens.push({ type: "number", value: Number(text.slice(numberStart, index)) })
      continue
    }

    if (isLetter(character)) {
      var nameStart = index
      while (index < text.length && isLetter(text.charAt(index))) index++
      tokens.push({ type: "name", value: text.slice(nameStart, index).toLowerCase() })
      continue
    }

    // The typographic operators are what a phone keyboard and a pasted formula
    // produce, and they mean exactly what their ASCII twins do.
    if (character === "×") { tokens.push({ type: "*" }); index++; continue }
    if (character === "÷") { tokens.push({ type: "/" }); index++; continue }
    if (character === "−") { tokens.push({ type: "-" }); index++; continue }

    if ("+-*/%^(),".indexOf(character) >= 0) {
      tokens.push({ type: character })
      index++
      continue
    }

    return null
  }

  return tokens
}

function peek(state) {
  return state.index < state.tokens.length ? state.tokens[state.index] : null
}

function take(state) {
  return state.index < state.tokens.length ? state.tokens[state.index++] : null
}

// Values carry whether they were written as a percentage, because that decides
// what the operator above them means: 20% of a product is a fifth of it, but
// 20% added to a sum is a fifth of what it is being added to. Only the operator
// directly above a percentage sees the flag -- parentheses close over it, so
// (20%) is plainly 0.2.
function plain(value) {
  return { value: value, percent: false }
}

// A percentage read as the number it stands for: 20% is 0.2. Everything except
// the till-style + and - below wants this rather than the raw 20, so every
// operator, function argument, group and final result goes through it.
function fraction(operand) {
  return operand.percent ? operand.value / 100 : operand.value
}

function shareOf(total, percentage) {
  return total * percentage / 100
}

// Recursive descent, one function per precedence level. Every one of them
// returns null to mean "not a valid expression from here", which is why the
// callers compare against null rather than testing truthiness: 0 is a perfectly
// good answer.
function parseSum(state) {
  var left = parseProduct(state)
  if (left === null) return null

  for (;;) {
    var token = peek(state)
    if (!token || (token.type !== "+" && token.type !== "-")) return left
    take(state)
    state.operators++

    var right = parseProduct(state)
    if (right === null) return null

    // "178000 - 20%" takes a fifth off 178000; it does not subtract 0.2. The
    // left side is a plain value by then -- a percentage on the left is the
    // fraction it names, so "20% + 100" is 100.2 and not 120.
    var total = fraction(left)
    var addend = right.percent ? shareOf(total, right.value) : right.value
    left = plain(token.type === "+" ? total + addend : total - addend)
  }
}

function parseProduct(state) {
  var left = parsePower(state)
  if (left === null) return null

  for (;;) {
    var token = peek(state)
    // "of" multiplies, which is all "20% of 80" is asking for.
    var isOf = token !== null && token.type === "name" && token.value === "of"
    if (!token || (token.type !== "*" && token.type !== "/" && !isOf)) return left
    take(state)
    state.operators++

    var right = parsePower(state)
    if (right === null) return null

    // Multiplied or divided, a percentage is simply its fraction: the operand
    // it meets is the whole that it is a part of.
    var leftValue = fraction(left)
    var rightValue = fraction(right)
    left = plain(token.type === "/" ? leftValue / rightValue : leftValue * rightValue)
  }
}

// Right associative, so 2^3^2 is 2^9 rather than 64.
function parsePower(state) {
  var base = parseUnary(state)
  if (base === null) return null

  var token = peek(state)
  if (!token || token.type !== "^") return base
  take(state)
  state.operators++

  var exponent = parsePower(state)
  if (exponent === null) return null
  return plain(Math.pow(fraction(base), fraction(exponent)))
}

function parseUnary(state) {
  var token = peek(state)
  if (token && (token.type === "-" || token.type === "+")) {
    take(state)
    var operand = parseUnary(state)
    if (operand === null) return null
    if (token.type !== "-") return operand
    return { value: -operand.value, percent: operand.percent }
  }

  var value = parsePrimary(state)
  if (value === null) return null

  // Postfix, so "%" is a percentage and not a remainder. A search box is asked
  // for "20% off" far more often than for a modulo, and the two cannot share
  // the sign: one wants an operand on its right and the other refuses one.
  var next = peek(state)
  if (next && next.type === "%") {
    take(state)
    state.operators++
    return { value: value.value, percent: true }
  }

  return value
}

function parsePrimary(state) {
  var token = take(state)
  if (!token) return null

  if (token.type === "number") return plain(token.value)

  if (token.type === "(") {
    // Deliberately not counted as an operation: grouping computes nothing on
    // its own, and counting it would answer "(5)" with 5. Whatever is inside
    // raises the count itself if it is worth answering.
    var grouped = parseSum(state)
    if (grouped === null) return null
    var close = take(state)
    if (!close || close.type !== ")") return null
    return plain(fraction(grouped))
  }

  if (token.type === "name") {
    if (CONSTANTS.hasOwnProperty(token.value)) return plain(CONSTANTS[token.value])
    if (!FUNCTIONS.hasOwnProperty(token.value)) return null
    return parseCall(state, FUNCTIONS[token.value])
  }

  return null
}

function parseCall(state, callee) {
  var open = take(state)
  if (!open || open.type !== "(") return null
  state.operators++

  var args = []
  var next = peek(state)
  if (next && next.type === ")") {
    take(state)
  } else {
    for (;;) {
      var argument = parseSum(state)
      if (argument === null) return null
      args.push(fraction(argument))

      var separator = take(state)
      if (!separator) return null
      if (separator.type === ")") break
      if (separator.type !== ",") return null
    }
  }

  // Both ends of the range, so a fixed-arity function does not quietly drop
  // what it was handed: sqrt(4, 9) is malformed, not 2.
  if (args.length < callee.arity || args.length > callee.maxArity) return null
  return plain(callee.apply(args))
}

function evaluateExpression(text) {
  var tokens = tokenize(text)
  if (!tokens || tokens.length === 0) return null

  var state = { tokens: tokens, index: 0, operators: 0 }
  var parsed = parseSum(state)
  if (parsed === null) return null
  // Anything left over means the query only started out looking like a sum.
  if (state.index !== tokens.length) return null

  // A percentage standing on its own is the fraction it names: "20%" is 0.2.
  var value = fraction(parsed)
  if (typeof value !== "number" || !isFinite(value)) return null

  return { value: value, operators: state.operators }
}

function lookupUnit(name) {
  var key = String(name || "").toLowerCase().replace(/[°\s]/g, "")
  if (!key) return ""
  if (UNITS.hasOwnProperty(key)) return key
  if (ALIASES.hasOwnProperty(key)) return ALIASES[key]

  // Plurals, without a second row per unit in the tables. The length guard
  // keeps "s" itself -- seconds -- from being read as a plural of nothing.
  if (key.length > 2 && key.charAt(key.length - 1) === "s") return lookupUnit(key.slice(0, -1))
  return ""
}

function symbolFor(unit) {
  return SYMBOLS.hasOwnProperty(unit) ? SYMBOLS[unit] : unit
}

// Temperature scales share no zero, so they convert through kelvin instead of
// through a factor.
function toKelvin(value, unit) {
  if (unit === "c") return value + 273.15
  if (unit === "f") return (value - 32) * 5 / 9 + 273.15
  return value
}

function fromKelvin(kelvin, unit) {
  if (unit === "c") return kelvin - 273.15
  if (unit === "f") return (kelvin - 273.15) * 9 / 5 + 32
  return kelvin
}

function convert(value, from, to) {
  var source = UNITS[from]
  var target = UNITS[to]
  if (!source || !target || source.dimension !== target.dimension) return null
  if (source.dimension === "temperature") return fromKelvin(toKelvin(value, from), to)
  return value * source.factor / target.factor
}

// The amount is a whole expression with the unit stuck on the end, so
// "2 * 3 kg" and "20km" both split cleanly. `spaced` reports whether the unit
// stood on its own, which is what tells a quantity from a search term.
function splitAmount(text) {
  var match = String(text).match(/^(.*?)(\s*)([a-zA-Z°]+)$/)
  if (!match || !match[1].trim()) return null

  var unit = lookupUnit(match[3])
  if (!unit) return null

  var amount = evaluateExpression(match[1])
  if (!amount) return null

  return { value: amount.value, unit: unit, spaced: match[2].length > 0, written: match[3] }
}

// Splits on the connector words, last one first. Order matters for "10 in to
// cm": read from the left, "in" looks like the connector and leaves "to cm" as
// the target unit; read from the right, "to" splits it the way it was meant.
function conversionSplits(text) {
  var words = text.split(/\s+/)
  var splits = []

  for (var i = words.length - 2; i > 0; i--) {
    if (words[i].toLowerCase() !== "to" && words[i].toLowerCase() !== "in") continue
    splits.push({
      amount: words.slice(0, i).join(" "),
      target: words.slice(i + 1).join(" ")
    })
  }

  return splits
}

function evaluateConversion(text) {
  var splits = conversionSplits(text)

  for (var i = 0; i < splits.length; i++) {
    var target = lookupUnit(splits[i].target)
    if (!target) continue

    var amount = splitAmount(splits[i].amount)
    if (!amount) continue

    var converted = convert(amount.value, amount.unit, target)
    if (converted === null || !isFinite(converted)) continue

    return [formatNumber(converted) + " " + symbolFor(target)]
  }

  return null
}

// A quantity with no target named: answer with the units its own readers want.
//
// A unit written against its number has to be at least two letters. Every
// single-letter unit is also the tail of something people search for -- 4k, 3d,
// 5g, 7z -- and answering those with a temperature or a duration is worse than
// not answering. Written with a space, "20 c" is unambiguous and allowed.
function evaluateQuantity(text) {
  var amount = splitAmount(text)
  if (!amount) return null
  if (!amount.spaced && amount.written.length < 2) return null

  var peers = PEERS[amount.unit]
  if (!peers) return null

  var results = []
  for (var i = 0; i < peers.length; i++) {
    var converted = convert(amount.value, amount.unit, peers[i])
    if (converted === null || !isFinite(converted)) continue
    results.push(formatNumber(converted) + " " + symbolFor(peers[i]))
  }

  return results.length > 0 ? results : null
}

// Twelve significant digits: enough that a conversion keeps its precision, few
// enough that 0.1 + 0.2 comes back as 0.3 rather than as the float that
// actually holds. Number() drops the trailing zeros toPrecision leaves behind.
function formatNumber(value) {
  if (value === 0) return "0"
  return String(Number(value.toPrecision(12)))
}

// The results as they should be shown, most useful first, or null when the
// query is not a calculation -- which is nearly every query, so this stays
// cheap to ask. A list because a bare quantity has more than one right answer.
function evaluate(query) {
  var text = String(query || "").trim()
  if (!text) return null

  var converted = evaluateConversion(text)
  if (converted !== null) return converted

  var quantity = evaluateQuantity(text)
  if (quantity !== null) return quantity

  var math = evaluateExpression(text)
  if (!math) return null
  // A bare number or constant is not a calculation. "5" typed into a search box
  // is someone looking for 5, and answering it with "5" is noise.
  if (math.operators === 0) return null

  return [formatNumber(math.value)]
}

if (typeof module !== "undefined") {
  module.exports = {
    evaluate: evaluate,
    formatNumber: formatNumber,
    lookupUnit: lookupUnit,
    convert: convert
  }
}
