#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const calendar = requireFromRoot('shell/plugins/panels/clock/Model.js')
const panelSource = fs.readFileSync(root + '/shell/plugins/panels/clock/Panel.qml', 'utf8')
const widgetSource = fs.readFileSync(root + '/shell/plugins/panels/clock/BarWidget.qml', 'utf8')

// ---- week start resolution
assertEqual(calendar.normalizedWeekStart('monday', 0), 1, 'calendar reads a named week start')
assertEqual(calendar.normalizedWeekStart('SUN', 1), 0, 'calendar reads an abbreviated week start')
assertEqual(calendar.normalizedWeekStart(6, 1), 6, 'calendar reads a numeric week start')
assertEqual(calendar.normalizedWeekStart(null, 0), 0, 'calendar falls back to the locale first day')
assertEqual(calendar.normalizedWeekStart('garbage', 0), 0, 'calendar falls back when the setting is unparseable')
assertEqual(calendar.normalizedWeekStart(undefined, undefined), 1, 'calendar defaults to Monday without a locale')

assertEqual(calendar.weekStartSettingName(0), 'sunday', 'calendar persists Sunday by name')
assertEqual(calendar.weekStartSettingName(1), 'monday', 'calendar persists Monday by name')

assertEqual(calendar.toggledWeekStart(1), 0, 'calendar toggles Monday to Sunday')
assertEqual(calendar.toggledWeekStart(0), 1, 'calendar toggles Sunday to Monday')
assertEqual(calendar.toggledWeekStart(6), 1, 'calendar toggles an exotic week start to Monday')

assertDeepEqual(calendar.weekdayOrder(1), [1, 2, 3, 4, 5, 6, 0], 'calendar orders weekdays from Monday')
assertDeepEqual(calendar.weekdayOrder(0), [0, 1, 2, 3, 4, 5, 6], 'calendar orders weekdays from Sunday')

// ---- ISO week numbers, matching the clock widget's 'ww' token
assertEqual(calendar.isoWeek(2026, 0, 1), 1, 'calendar numbers a Thursday January 1 as week 1')
assertEqual(calendar.isoWeek(2021, 0, 1), 53, 'calendar numbers early January into the previous ISO year')
assertEqual(calendar.isoWeek(2026, 11, 31), 53, 'calendar numbers the last week of a long year')
assertEqual(calendar.isoWeek(2026, 6, 26), 30, 'calendar numbers a midsummer Sunday')

// ---- day-of-year arithmetic behind the hero stats
assertEqual(calendar.dayOfYear(2026, 6, 26), 207, 'calendar counts the day of the year')
assertEqual(calendar.yearProgressPercent(2026, 0, 1), 0, 'calendar starts the year at zero percent done')
assertEqual(calendar.yearProgressPercent(2026, 6, 26), 56, 'calendar reports the share of the year behind you')
assertEqual(calendar.yearProgressPercent(2026, 11, 31), 100, 'calendar finishes the year at a hundred percent')
assertEqual(calendar.yearProgressPercent(2024, 11, 31), 100, 'calendar finishes a leap year too')

// ---- memento mori
// A birth year rather than an age, so the bar keeps counting on its own.
assertEqual(calendar.parseBirthYear('1979', 2026), 1979, 'calendar reads a birth year')
assertEqual(calendar.parseBirthYear(1979, 2026), 1979, 'calendar reads a numeric birth year')
assertEqual(calendar.parseBirthYear(' 1979 ', 2026), 1979, 'calendar trims a birth year')
assertEqual(calendar.parseBirthYear('2026', 2026), 2026, 'calendar accepts the current year')
assertEqual(calendar.parseBirthYear('2027', 2026), 0, 'calendar rejects a birth year in the future')
assertEqual(calendar.parseBirthYear('1905', 2026), 0, 'calendar rejects an implausibly distant birth year')
assertEqual(calendar.parseBirthYear('79', 2026), 0, 'calendar rejects a two-digit year')
assertEqual(calendar.parseBirthYear('', 2026), 0, 'calendar treats a blank birth year as unset')
assertEqual(calendar.parseBirthYear('abc', 2026), 0, 'calendar treats a non-numeric birth year as unset')

assertEqual(calendar.ageFromBirthYear('1979', 2026), 47, 'calendar derives an age from a birth year')
assertEqual(calendar.ageFromBirthYear('1979', 2027), 48, 'calendar keeps counting as the years pass')
assertEqual(calendar.ageFromBirthYear('2026', 2026), 0, 'calendar makes someone born this year zero')
assertEqual(calendar.ageFromBirthYear('', 2026), 0, 'calendar derives no age without a birth year')

assertEqual(calendar.parseAge('47'), 47, 'calendar reads an age')
assertEqual(calendar.parseAge(47), 47, 'calendar reads a numeric age')
assertEqual(calendar.parseAge(' 47 '), 47, 'calendar trims an age')
assertEqual(calendar.parseAge(''), 0, 'calendar treats a blank age as unset')
assertEqual(calendar.parseAge('0'), 0, 'calendar treats zero as unset')
assertEqual(calendar.parseAge('-3'), 0, 'calendar treats a negative age as unset')
assertEqual(calendar.parseAge('121'), 0, 'calendar treats an implausible age as unset')
assertEqual(calendar.parseAge('abc'), 0, 'calendar treats a non-numeric age as unset')
assertEqual(calendar.parseAge('4.5'), 0, 'calendar treats a fractional age as unset')
assertEqual(calendar.parseLifeExpectancy('65'), 65, 'calendar reads a life expectancy')
assertEqual(calendar.parseLifeExpectancy(''), 90, 'calendar defaults the life expectancy to ninety')
assertEqual(calendar.parseLifeExpectancy(0), 90, 'calendar defaults an unset life expectancy')
assertEqual(calendar.parseLifeExpectancy('abc'), 90, 'calendar defaults a non-numeric life expectancy')
assertEqual(calendar.parseLifeExpectancy('200'), 90, 'calendar defaults an implausible life expectancy')

assertEqual(calendar.lifeProgressPercent(45, 90), 50, 'calendar measures a life against the expectancy given')
assertEqual(calendar.lifeProgressPercent(45, 65), 69, 'calendar honours a shorter expectancy')
assertEqual(calendar.lifeProgressPercent(45, ''), 50, 'calendar falls back to ninety when no expectancy is set')
assertEqual(calendar.lifeProgressPercent(90, 90), 100, 'calendar fills the life bar at the expectancy')
assertEqual(calendar.lifeProgressPercent(80, 65), 100, 'calendar never overfills the life bar')
assertEqual(calendar.lifeProgressPercent(0, 90), 0, 'calendar leaves the life bar empty when no age is set')
assertEqual(calendar.daysInYear(2024), 366, 'calendar knows leap years are longer')
assertEqual(calendar.daysInYear(2026), 365, 'calendar knows common years')

// ---- month grid
const july = calendar.monthGrid(2026, 6, 1, '2026-07-26')
assertEqual(july.length, 6, 'calendar always draws six week rows')
assert(july.every(week => week.days.length === 7), 'calendar always draws seven day columns')
assertDeepEqual(july.map(week => week.week), [27, 28, 29, 30, 31, 32], 'calendar numbers every row by ISO week')
assertDeepEqual(july[0].days.map(day => day.day), [29, 30, 1, 2, 3, 4, 5], 'calendar pads the first row with the previous month')
assertDeepEqual(july[0].days.map(day => day.inMonth), [false, false, true, true, true, true, true], 'calendar marks padding days as outside the month')
assertDeepEqual(july[0].days.map(day => day.weekend), [false, false, false, false, false, true, true], 'calendar marks Saturday and Sunday as the weekend')

assertDeepEqual(
  july.flatMap(week => week.days).filter(day => day.today).map(day => day.key),
  ['2026-07-26'],
  'calendar marks exactly one cell as today'
)
assert(july.flatMap(week => week.days).every(day => day.cursor === undefined), 'calendar grid carries no selection state')

// Both conventions land on the same ISO week numbers, because every row is
// numbered by the ISO week owning its Thursday.
const julySunday = calendar.monthGrid(2026, 6, 0, '')
assertDeepEqual(julySunday[0].days.map(day => day.day), [28, 29, 30, 1, 2, 3, 4], 'calendar shifts the grid for a Sunday week start')
assertDeepEqual(julySunday.map(week => week.week), [27, 28, 29, 30, 31, 32], 'calendar keeps ISO week numbers across week starts')

const januarySunday = calendar.monthGrid(2021, 0, 0, '')
assertEqual(januarySunday[0].week, 53, 'calendar carries the previous ISO year into a straddling first row')

// ---- stepping
assertDeepEqual(calendar.stepMonth(2026, 0, 1), { year: 2026, month: 1 }, 'calendar steps to the next month')
assertDeepEqual(calendar.stepMonth(2026, 0, -1), { year: 2025, month: 11 }, 'calendar steps back across the new year')
assertDeepEqual(calendar.stepMonth(2026, 11, 1), { year: 2027, month: 0 }, 'calendar steps forward across the new year')
assertDeepEqual(calendar.stepMonth(2026, 6, 12), { year: 2027, month: 6 }, 'calendar steps a whole year at a time')

assertEqual(calendar.dateKey(2026, 0, 5), '2026-01-05', 'calendar zero-pads date keys')
assertEqual(calendar.keyForDate(new Date(2026, 6, 26)), '2026-07-26', 'calendar keys a Date the same way')

// ---- bar label format ring
// The order must not depend on which entry is current: cycling writes the
// result back to shell.json, so a self-reordering ring would ping-pong.
const ring = calendar.clockFormatRing('dddd HH:mm', "d MMMM 'W'ww yyyy", calendar.clockFormats(false))
assertDeepEqual(ring, calendar.clockFormats(false), 'clock rings the stock presets in their own order')
assertEqual(new Set(ring).size, ring.length, 'clock never offers the same format twice')

assertDeepEqual(
  calendar.clockFormatRing("d MMMM 'W'ww yyyy", 'dddd HH:mm', calendar.clockFormats(false)),
  ring,
  'clock keeps the ring order steady as the current format moves through it'
)
assertDeepEqual(
  calendar.clockFormatRing('HH:mm:ss', '', ['HH:mm', 'dddd HH:mm']),
  ['HH:mm', 'dddd HH:mm', 'HH:mm:ss'],
  'clock appends a hand-written format to the end of the ring'
)
assertDeepEqual(calendar.clockFormatRing('', '', []), ['HH:mm'], 'clock keeps a usable format when nothing is configured')

assertEqual(calendar.nextClockFormat(ring, ring[0]), ring[1], 'clock steps to the next format')
assertEqual(calendar.nextClockFormat(ring, ring[ring.length - 1]), ring[0], 'clock wraps the format ring')
assertEqual(calendar.nextClockFormat(ring, 'HH:mm:ss'), ring[0], 'clock starts at the top from a format outside the ring')
assertEqual(calendar.clockFormats(true)[0], 'HH\n\u2014\nmm', 'clock keeps stacked formats for vertical bars')
assertEqual(calendar.isoWeekLiteral(2026, 0, 5), '02', 'clock zero-pads the ISO week token')

// ---- widget wiring
assert(/moduleName: "omarchy\.clock"/.test(panelSource), 'calendar panel declares its module name')
assert(/ipcTarget: "omarchy\.clock"/.test(panelSource), 'calendar panel registers its IPC target')
assert(/manageIpc: false/.test(panelSource), 'calendar panel leaves the IPC target to the bar widget')
assert(/anchorItem: root\.anchorItem/.test(panelSource), 'calendar panel anchors to the host widget button')
assert(/function toggleWeekStart\(\)/.test(panelSource), 'calendar panel exposes a week start toggle')
assert(/setting\("weekStartDay", null\)/.test(panelSource) && /persistSettings\(\{ weekStartDay:/.test(panelSource), 'calendar reads and writes the week start as weekStartDay')
assert(/updateEntryInline/.test(panelSource), 'calendar panel persists the week start to shell.json')
assert(/function moveMonth\(delta\)/.test(panelSource), 'calendar panel steps between months')
assert(!/property bool onToday/.test(panelSource) && !/root\.onToday/.test(panelSource), 'calendar panel avoids the on-prefixed property name QML reads as a signal handler')
assert(/readonly property bool viewingCurrentMonth:/.test(panelSource), 'calendar panel tracks whether the current month is on screen')
assert(!/MouseArea/.test(panelSource.slice(panelSource.indexOf('model: modelData.days'), panelSource.indexOf('// Hairline'))), 'calendar day cells are not selectable')
assert(/yearDone: Model\.yearProgress\(today\./.test(panelSource), 'calendar year bar stays pinned to today while months are stepped')
assert(/Qt\.callLater\(function\(\) \{\s*\n\s*if \(root\.opened\) setCenterHoverRevealSuppressed\(true\)/.test(panelSource), 'calendar claims the shared hover-reveal flag after the popout handoff, so the panel taking over wins')
assert(/function close\(\) \{\s*\n\s*setCenterHoverRevealSuppressed\(false\)/.test(panelSource), 'calendar always releases the shared hover-reveal flag on close')
assert(/width: Math\.max\(calendarScroll\.width, gridColumn\.width\)/.test(panelSource), 'calendar scrolls rather than clipping the grid on a narrow popup')
assert(/enabled: !root\.viewingCurrentMonth/.test(panelSource) && /onClicked: root\.goToToday\(\)/.test(panelSource), 'calendar hero returns to today once the view has stepped away')
assert(!/clampMonth/.test(panelSource), 'calendar steps freely into future months')
assert(/Qt\.formatDate\(root\.today, "MMMM d"\)/.test(panelSource), 'calendar hero spells out today')
assert(/id: yearLabel/.test(panelSource) && /root\.yearDone/.test(panelSource), 'calendar panel shows the year progress bar')

// The memento mori bar is opt-in: double-tapping the year bar asks for an age,
// and nothing shows until one has been given.
assert(/onDoubleTapped: root\.startEditingLife\(\)/.test(panelSource), 'calendar asks for an age when the year bar is double-tapped')
assert(/persistSettings\(\{ birthYear: born, lifeExpectancy: span \}\)/.test(panelSource), 'calendar saves birth year and expectancy together, so neither lands on a stale copy')
assert(/readonly property int birthYear: Model\.parseBirthYear\(setting\("birthYear", 0\)/.test(panelSource), 'calendar reads the saved birth year back')
assert(/readonly property int age: Model\.ageFromBirthYear\(birthYear/.test(panelSource), 'calendar derives the age from the stored birth year')
assert(/readonly property int lifeExpectancy: Model\.parseLifeExpectancy\(setting\("lifeExpectancy", 0\)\)/.test(panelSource), 'calendar reads the saved expectancy back')
assert(/id: expectancyField/.test(panelSource) && /id: bornField/.test(panelSource), 'calendar offers both inputs')
assert(/visible: root\.editingLife\s*\n\s*anchors\.horizontalCenter: parent\.horizontalCenter/.test(panelSource), 'calendar centers the inputs over the bar they replace')
assert(/visible: root\.birthYear > 0/.test(panelSource), 'calendar hides the life bar until a birth year is known')
assert(/text: "LIFE"/.test(panelSource) && /root\.lifeDone/.test(panelSource), 'calendar shows the life bar')
assert(/text: "Memento Mori"/.test(panelSource), 'calendar names the life bar on hover')
assert(/onDoubleTapped: root\.clearLife\(\)/.test(panelSource), 'calendar puts the life bar away when it is double-tapped')
assert(/persistSettings\(\{ birthYear: 0 \}\)/.test(panelSource), 'calendar clears the birth year to hide the life bar')
assertEqual(calendar.parseBirthYear(0, 2026), 0, 'a cleared birth year reads back as unset')
assert(/blocked: root\.editingLife/.test(panelSource), 'calendar lets the inputs have the keyboard while they are up')
assert(/if \(root\.editingLife\) root\.cancelEditingLife\(\)/.test(panelSource), 'calendar drops a half-finished edit when the panel closes')

assert(/source: Qt\.resolvedUrl\("Panel\.qml"\)/.test(widgetSource), 'clock widget hosts the calendar panel')
assert(/readonly property bool opened:/.test(widgetSource), 'clock widget exposes the panel open state to shell routing')
assert(/Qt\.RightButton\) root\.cycleFormat\(\)/.test(widgetSource), 'clock right click cycles the label format')
assert(/readonly property string activeFormat: configuredFormat/.test(widgetSource), 'clock shows the format it has stored')
assert(/entry\[vertical \? "verticalFormat" : "format"\] = next/.test(widgetSource) && /updateEntryInline/.test(widgetSource), 'clock writes a cycled format back to shell.json')
assert(!/formatIndex/.test(widgetSource), 'clock keeps no session-only format position')
assert(/else root\.togglePanel\(\)/.test(widgetSource), 'clock left click reveals the calendar')
assert(/omarchy-menu-timezone/.test(widgetSource), 'clock keeps the timezone picker on middle click')

// The bar identifies a panel by the widget in its slot, so the nested panel
// has to present the host widget rather than itself.
assert(/owner: root\.barIdentity/.test(panelSource), 'calendar panel gives the bar its host widget as popout identity')
assert(/switchPanelFrom\(root\.barIdentity, direction\)/.test(panelSource), 'calendar panel switches panels as its host widget')
assert(/hostWidget" in target\) target\.hostWidget = root/.test(widgetSource), 'clock widget injects itself as the panel host')
assert(/readonly property bool popoutSwitchClosing:/.test(widgetSource) && /function closeForPopoutSwitch\(\)/.test(widgetSource), 'clock widget forwards the popout-switch handshake')
assert(/openPanelIndicatorWidth: button\.labelWidth/.test(widgetSource), 'clock sizes the open-panel dot to its label')
assert(/openPanelIndicatorHeight: Math\.max/.test(widgetSource), 'clock sizes the vertical open-panel dot to one stacked line')
const barSource = fs.readFileSync(root + '/shell/plugins/bar/Bar.qml', 'utf8')
assert(/openPanelIndicatorWidth/.test(barSource) && /openPanelIndicatorHeight/.test(barSource), 'bar honours a widget-supplied open-panel dot size on both axes')
assert(/height: root\.vertical \? slot\.panelIndicatorExtent : Style\.space\(2\)/.test(barSource), 'bar sizes the vertical dot from the same hint as the horizontal one')
assert(/readonly property real labelWidth:/.test(fs.readFileSync(root + '/shell/Ui/WidgetButton.qml', 'utf8')), 'widget buttons expose their painted label width')

// A horizontal wheel reports angleDelta.y === 0; without the guard every one
// of them would read as a forward step.
assert(/if \(event\.angleDelta\.y === 0\) return/.test(panelSource), 'calendar ignores wheel events with no vertical delta')
JS

shell_json=$(cd "$ROOT" && jq -r '[.bar.layout.center[].id] | join(",")' config/omarchy/shell.json)
[[ $shell_json == *"omarchy.clock"* ]] || fail "default bar layout includes the clock widget" "center: $shell_json"
[[ $shell_json != *"omarchy.calendar"* ]] || fail "clock hosts the calendar instead of a second bar pill" "center: $shell_json"
pass "default bar layout includes the clock widget"

grep -q 'o.bind("SUPER + CTRL + ALT + D", "Calendar", "omarchy-shell shell toggle omarchy.clock")' \
  "$ROOT/default/hypr/bindings/utilities.lua" ||
  fail "SUPER+CTRL+ALT+D toggles the calendar panel"
pass "SUPER+CTRL+ALT+D toggles the calendar panel"
