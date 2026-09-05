#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const menu = requireFromRoot('shell/plugins/menu/MenuModel.js')
const menuQml = fs.readFileSync(path.join(root, 'shell/plugins/menu/Menu.qml'), 'utf8')

const calcText = query => {
  const result = menu.calcResultForQuery(query)
  return result && result.text
}

assertEqual(calcText('2+3'), '5', 'menu calculates addition')
assertEqual(calcText('10-4'), '6', 'menu calculates subtraction')
assertEqual(calcText('6*7'), '42', 'menu calculates multiplication')
assertEqual(calcText('54000*2'), '108000', 'menu calculates a large multiplication')
assertEqual(calcText('8/2'), '4', 'menu calculates division')
assertEqual(calcText('2+3*4'), '14', 'menu respects operator precedence')
assertEqual(calcText('(2+3)*4'), '20', 'menu evaluates parentheses')
assertEqual(calcText('-5+3'), '-2', 'menu applies a leading unary sign')
assertEqual(calcText('3\u00d74'), '12', 'menu multiplies with the × glyph')
assertEqual(calcText('8\u00f72'), '4', 'menu divides with the ÷ glyph')
assertEqual(calcText('2.5*2'), '5', 'menu calculates decimals')
assertEqual(calcText('0.1+0.2'), '0.3', 'menu formats 0.1+0.2 without float noise')
    assertEqual(calcText('6x6'), '36', 'menu multiplies with x')
    assertEqual(calcText('50%'), '0.5', 'menu reads a lone percent as a fraction')
    assertEqual(calcText('5%200'), '10', 'menu reads juxtaposed percent as percent-of')
    assertEqual(calcText('2(3+4)'), '14', 'menu multiplies a juxtaposed parenthesis')
    assertEqual(calcText('1.2.3'), null, 'menu rejects number-on-number juxtaposition')
    assertEqual(calcText('5 5'), null, 'menu rejects two numbers side by side')

assertEqual(menu.calcResultForQuery('3,5*2'), null, 'menu rejects a comma decimal separator')
assertEqual(menu.calcResultForQuery('1500abc'), null, 'menu rejects trailing garbage')
assertEqual(menu.calcResultForQuery('42'), null, 'menu rejects a lone number with no operator')
assertEqual(menu.calcResultForQuery(''), null, 'menu rejects an empty query')
assertEqual(menu.calcResultForQuery('1/0'), null, 'menu rejects division by zero')
assertEqual(menu.calcResultForQuery('(2+3'), null, 'menu rejects unbalanced parentheses')
assertEqual(menu.calcResultForQuery('firefox'), null, 'menu leaves a plain word search alone')

assert(
  /var calcResult = MenuModel\.calcResultForQuery\(query\)\s*\n\s*rows = currentRows\.concat\(drilldownRows\)\s*\n\s*if \(calcResult\) \{/.test(menuQml),
  'menu evaluates the calculator after sorting search rows and before showing them'
)
assert(
  /rows\.unshift\(\{\s*\n\s*itemId: "calc",\s*\n\s*disabled: false,\s*\n\s*kind: "action",\s*\n\s*icon: "",/.test(menuQml),
  'menu prepends the calculator row without a leading icon'
)
assert(
  /label: calcText,/.test(menuQml)
    && /detail: "",/.test(menuQml)
    && /action: "printf '%s' " \+ Util\.shellQuote\(calcText\) \+ " \| wl-copy",/.test(menuQml),
  'menu labels the calculator row with its result and copies it through wl-copy'
)
assert(
  /horizontalAlignment: row\.isCalc \? Text\.AlignHCenter : Text\.AlignLeft/.test(menuQml)
    && /row\.isCalc \? "\\uf0c5" : ""\)/.test(menuQml),
  'menu centers the calculator result and keeps a copy glyph on the right'
    )
    assert(
      /rowReservedBorderRight \+ Style\.space\(8\) \+ \(row\.isCalc \? Style\.space\(8\) : 0\)/.test(menuQml),
      'menu gives the calculator copy glyph extra right margin'
    )
JS
