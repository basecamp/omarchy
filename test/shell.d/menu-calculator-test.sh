#!/bin/bash
source "$(dirname "$0")/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')

const calculator = requireFromRoot('shell/plugins/menu/Calculator.js')

assertDeepEqual(calculator.evaluate('2+2'), ['4'], 'adds')
assertDeepEqual(calculator.evaluate('10 / 4'), ['2.5'], 'divides into a fraction')
assertDeepEqual(calculator.evaluate('(1+2)*3'), ['9'], 'respects parentheses')
assertDeepEqual(calculator.evaluate('2^3^2'), ['512'], 'exponentiation is right associative')
assertDeepEqual(calculator.evaluate('-5 + 3'), ['-2'], 'reads a leading minus as a sign')
assertDeepEqual(calculator.evaluate('2 × 3'), ['6'], 'accepts the typographic multiplication sign')
assertDeepEqual(calculator.evaluate('sqrt(16)'), ['4'], 'calls a function')
assertDeepEqual(calculator.evaluate('max(3, 9, 2)'), ['9'], 'passes every argument to a variadic function')
assertDeepEqual(calculator.evaluate('0.1 + 0.2'), ['0.3'], 'rounds float noise away')
assertDeepEqual(calculator.evaluate('1e6 / 4'), ['250000'], 'reads scientific notation')
assertDeepEqual(calculator.evaluate('round(3.14159, 2)'), ['3.14'], 'rounds to a given number of places')

// "%" is a percentage, not a remainder: the two cannot share the sign, since
// one wants an operand on its right and the other refuses one.
assertDeepEqual(calculator.evaluate('178000*20%'), ['35600'], 'multiplies by a percentage')
assertDeepEqual(calculator.evaluate('20% of 178000'), ['35600'], 'reads "of" as taking a share')
assertDeepEqual(calculator.evaluate('178000+20%'), ['213600'], 'adds a percentage of what it is added to')
assertDeepEqual(calculator.evaluate('178000-20%'), ['142400'], 'subtracts a percentage of what it is taken from')
assertDeepEqual(calculator.evaluate('20%'), ['0.2'], 'a percentage on its own is its fraction')
assertDeepEqual(calculator.evaluate('178000 * 20% + 500'), ['36100'], 'keeps precedence around a percentage')
assertDeepEqual(calculator.evaluate('(20%) * 50'), ['10'], 'parentheses close over the percentage')
assertDeepEqual(calculator.evaluate('20% + 100'), ['100.2'], 'a percentage on the left is its own fraction, not a share of what follows')
assertDeepEqual(calculator.evaluate('20% + 20%'), ['0.24'], 'two percentages keep both readings')
assertDeepEqual(calculator.evaluate('2^50%'), ['1.41421356237'], 'an exponent written as a percentage is its fraction')
assertDeepEqual(calculator.evaluate('20%^2'), ['0.04'], 'a base written as a percentage is its fraction')

// Grouping computes nothing on its own, so it cannot be what makes a query an
// expression -- otherwise "(5)" would answer 5.
assertEqual(calculator.evaluate('(5)'), null, 'parentheses alone are not a calculation')
assertEqual(calculator.evaluate('(pi)'), null, 'a grouped constant is not a calculation')

// An argument a function would ignore is a typo, not an expression.
assertEqual(calculator.evaluate('sqrt(4, 9)'), null, 'refuses an extra argument instead of dropping it')
assertEqual(calculator.evaluate('round(1.234, 2, 3)'), null, 'refuses a third argument to round')
assertEqual(calculator.evaluate('min(5)'), null, 'refuses a missing argument')
assertDeepEqual(calculator.evaluate('50% of 80 kg'), ['88.184904874 lb', '40000 g'], 'expands a quantity computed from a share')

assertDeepEqual(calculator.evaluate('20 km to mi'), ['12.4274238447 mi'], 'converts length')
assertDeepEqual(calculator.evaluate('2 lb to kg'), ['0.90718474 kg'], 'converts mass')
assertDeepEqual(calculator.evaluate('90 min to h'), ['1.5 h'], 'converts time')
assertDeepEqual(calculator.evaluate('1 gb to mb'), ['1000 MB'], 'converts decimal data units')
assertDeepEqual(calculator.evaluate('1 gib to mib'), ['1024 MiB'], 'converts binary data units')
assertDeepEqual(calculator.evaluate('1 gal to l'), ['3.785411784 L'], 'converts volume')
assertDeepEqual(calculator.evaluate('100 f to c'), ['37.7777777778 °C'], 'converts temperature across offsets')
assertDeepEqual(calculator.evaluate('0 c to f'), ['32 °F'], 'converts freezing point')
assertDeepEqual(calculator.evaluate('72f to c'), ['22.2222222222 °C'], 'reads a unit stuck to its number')
assertDeepEqual(calculator.evaluate('2 * 3 kg to lb'), ['13.2277357311 lb'], 'converts a computed amount')
assertDeepEqual(calculator.evaluate('5 kilometers to miles'), ['3.10685596119 mi'], 'reads plural long unit names')
assertDeepEqual(calculator.evaluate('2 lbs to kg'), ['0.90718474 kg'], 'reads a plural symbol without a table entry for it')

// "ton" is 1000 kg in most of the world and 907 kg in the US. An alias that is
// silently wrong by a tenth is worse than an alias that is missing.
assertEqual(calculator.evaluate('1 ton to kg'), null, 'refuses the ambiguous ton')
assertDeepEqual(calculator.evaluate('1 tonne to kg'), ['1000 kg'], 'accepts the unambiguous tonne')

// "in" is both a connector and a unit, so the split has to be read from the
// right: from the left this is 10 converted into a unit called "to cm".
assertDeepEqual(calculator.evaluate('10 in to cm'), ['25.4 cm'], 'prefers the rightmost connector')

// A quantity with no target named answers with the units its readers want.
assertDeepEqual(calculator.evaluate('5km'), ['3.10685596119 mi', '5000 m'], 'expands a bare length')
assertDeepEqual(calculator.evaluate('20kg'), ['44.092452437 lb', '20000 g'], 'expands a bare mass')
assertDeepEqual(calculator.evaluate('1gb'), ['0.931322574615 GiB', '1000 MB'], 'expands a bare data size across both bases')
assertDeepEqual(calculator.evaluate('20 c'), ['68 °F', '293.15 K'], 'expands a bare temperature')
assertDeepEqual(calculator.evaluate('2*3 kg'), ['13.2277357311 lb', '6000 g'], 'expands a computed bare quantity')

// Every single-letter unit is also the tail of something people search for, so
// against a number it needs the space that makes it a quantity.
assertEqual(calculator.evaluate('4k'), null, 'does not read 4k as kelvin')
assertEqual(calculator.evaluate('3d'), null, 'does not read 3d as days')
assertEqual(calculator.evaluate('5m'), null, 'does not read an attached single-letter unit')
assertDeepEqual(calculator.evaluate('5 m'), ['16.4041994751 ft', '500 cm'], 'reads the same unit once it is spaced')

assertEqual(calculator.evaluate(''), null, 'ignores an empty query')
assertEqual(calculator.evaluate('5'), null, 'a bare number is not a calculation')
assertEqual(calculator.evaluate('pi'), null, 'a bare constant is not a calculation')
assertEqual(calculator.evaluate('app'), null, 'ignores an ordinary search')
assertEqual(calculator.evaluate('zen browser'), null, 'ignores a two-word search')
assertEqual(calculator.evaluate('2 factorio'), null, 'ignores a search that starts with a number')
assertEqual(calculator.evaluate('1password'), null, 'ignores a search that starts with a number and ends in letters')
assertEqual(calculator.evaluate('20 km to kg'), null, 'refuses to convert across dimensions')
assertEqual(calculator.evaluate('1/0'), null, 'refuses a result that is not finite')

const menuQml = fs.readFileSync(path.join(root, 'shell/plugins/menu/Menu.qml'), 'utf8')

assert(
  menuQml.includes('Calculator.evaluate(query)') && menuQml.includes('rows.unshift(root.calculatorRow(calculation[c]))'),
  'menu search puts every calculated answer ahead of the matches'
)

assert(
  /action: "printf '%s' " \+ Util\.shellQuote\(result\) \+ " \| wl-copy"/.test(menuQml),
  'calculator row copies its result through a quoted argument'
)
JS
