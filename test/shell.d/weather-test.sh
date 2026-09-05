#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const weather = requireFromRoot('shell/plugins/panels/weather/Model.js')
const panelSource = fs.readFileSync(root + '/shell/plugins/panels/weather/Panel.qml', 'utf8')
const widgetSource = fs.readFileSync(root + '/shell/plugins/panels/weather/BarWidget.qml', 'utf8')

assertDeepEqual(weather.parseLocationFile('{"name": "Malibu", "latitude": 34.02577, "longitude": -118.7804}\n'), { name: 'Malibu', latitude: 34.02577, longitude: -118.7804 }, 'weather parses name plus coordinates from weather.json')
assertDeepEqual(weather.parseLocationFile('{"name": "New York"}'), { name: 'New York', latitude: null, longitude: null }, 'weather parses a name-only weather.json')
assertDeepEqual(weather.parseLocationFile('{"name": "Malibu", "latitude": 34.02577}'), { name: 'Malibu', latitude: null, longitude: null }, 'weather requires both coordinates')
assertDeepEqual(weather.parseLocationFile('not json'), { name: '', latitude: null, longitude: null }, 'weather treats an unparseable weather.json as auto-detect')
assertDeepEqual(weather.parseLocationFile(''), { name: '', latitude: null, longitude: null }, 'weather treats a missing weather.json as auto-detect')

assertDeepEqual(weather.locationCommit('  Pasadena  ', [], 0), { name: 'Pasadena', latitude: null, longitude: null }, 'weather commits typed locations before suggestions load')
assertDeepEqual(weather.locationCommit('', [], 0), { name: '', latitude: null, longitude: null }, 'weather commits an empty location as auto-detect')
assertDeepEqual(
  weather.locationCommit('mal', [{ name: 'Malibu', latitude: 34.02577, longitude: -118.7804 }], 0),
  { name: 'Malibu', latitude: 34.02577, longitude: -118.7804 },
  'weather commits the selected geocoding suggestion when available'
)

assertEqual(weather.wttrLocationQuery('Malibu', 34.02577, -118.7804), '34.02577,-118.7804', 'weather prefers coordinates for the wttr query')
assertEqual(weather.wttrLocationQuery('Malibu', '34.02577', '-118.7804'), '34.02577,-118.7804', 'weather accepts string coordinates')
assertEqual(weather.wttrLocationQuery('New York', null, null), 'New%20York', 'weather URL-encodes a name-only location')
assertEqual(weather.wttrLocationQuery('Malibu', 'nope', -118.7804), 'Malibu', 'weather ignores unparseable coordinates')
assertEqual(weather.wttrLocationQuery('', null, null), '', 'weather falls back to IP auto-detect without a location')
assertEqual(weather.wttrLocationQuery('  ', null, null), '', 'weather treats a blank location as unset')

assertDeepEqual(
  weather.parseGeocodingResults(JSON.stringify({
    results: [
      { name: 'Malibu', latitude: 34.02577, longitude: -118.7804, admin1: 'California', country: 'United States' },
      { name: 'Malibu', latitude: -7.18333, longitude: 29.65, admin1: 'Tanganyika', country: 'Democratic Republic of Congo' },
      { name: 'Broken', latitude: 1.0 },
      { name: 'Bare', latitude: 2.0, longitude: 3.0 }
    ]
  })),
  [
    { name: 'Malibu', description: 'California, United States', latitude: 34.02577, longitude: -118.7804 },
    { name: 'Malibu', description: 'Tanganyika, Democratic Republic of Congo', latitude: -7.18333, longitude: 29.65 },
    { name: 'Bare', description: '', latitude: 2.0, longitude: 3.0 }
  ],
  'weather parses geocoding suggestions and drops incomplete rows'
)
assertDeepEqual(weather.parseGeocodingResults('{}'), [], 'weather handles empty geocoding responses')
assertDeepEqual(weather.parseGeocodingResults('{'), [], 'weather handles invalid geocoding JSON')

assertEqual(weather.roundedTemp('21.6'), '22', 'weather rounds temperatures')
assertEqual(weather.roundedTemp('nope'), '', 'weather ignores invalid temperatures')
assertEqual(weather.formatTemp(72, true), '72°F', 'weather formats imperial temperatures')
assertEqual(weather.formatTemp(22, false), '22°C', 'weather formats metric temperatures')
assertEqual(weather.shouldUseImperial('', 'en_US', ''), true, 'weather falls back to US locale for imperial units')
assertEqual(weather.shouldUseImperial('', 'en_US', 'Denmark'), false, 'weather prefers reported metric country over US locale')
assertEqual(weather.shouldUseImperial('', 'da_DK', 'United States of America'), true, 'weather prefers reported imperial country over metric locale')
assertEqual(weather.shouldUseImperial('metric', 'en_US', 'United States of America'), false, 'weather metric override wins')
assertEqual(weather.shouldUseImperial('imperial', 'da_DK', 'Denmark'), true, 'weather imperial override wins')
assertEqual(weather.dayName('2026-05-25'), 'Monday', 'weather derives day names')

const openMeteo = {
  daily: {
    time: ['2026-05-25', '2026-05-26', '2026-05-27', '2026-05-28', '2026-05-29'],
    temperature_2m_max: [20.1, 21.6, 18.2, 17.9, 22.4],
    temperature_2m_min: [12.2, 13.1, 10.8, 9.2, 11.5],
    weather_code: [0, 63, 95, 3, 1]
  }
}

assertDeepEqual(
  weather.openMeteoForecastDays(openMeteo, '2026-05-25').map(day => ({
    date: day.date,
    maxtempC: day.maxtempC,
    mintempF: day.mintempF,
    code: day.openMeteoWeatherCode
  })),
  [
    { date: '2026-05-26', maxtempC: '22', mintempF: '56', code: 63 },
    { date: '2026-05-27', maxtempC: '18', mintempF: '51', code: 95 },
    { date: '2026-05-28', maxtempC: '18', mintempF: '49', code: 3 }
  ],
  'weather builds future Open-Meteo forecast days'
)

assertDeepEqual(
  weather.openMeteoCurrentCondition({ current: { temperature_2m: 21.4, apparent_temperature: 19.8, wind_speed_10m: 14.3, relative_humidity_2m: 63 } }),
  { temp_C: '21', temp_F: '71', FeelsLikeC: '20', FeelsLikeF: '68', windspeedKmph: '14', windspeedMiles: '9', humidity: '63' },
  'weather normalizes open-meteo current conditions to the wttr shape'
)
assertEqual(weather.openMeteoCurrentCondition({}), null, 'weather returns no current conditions without open-meteo data')
assertEqual(weather.openMeteoCurrentCondition({ current: {} }), null, 'weather requires a current temperature')

const wttr = {
  weather: [
    { date: '2026-05-25', maxtempC: '20', mintempC: '12' },
    { date: '2026-05-26', maxtempC: '22', mintempC: '13' }
  ]
}
assertEqual(weather.buildForecastDays(wttr, {}, '2026-05-25')[0].date, '2026-05-26', 'weather falls back to wttr forecast')
assertEqual(weather.bareTempForDay({ maxtempC: '22', mintempC: '13', maxtempF: '72', mintempF: '55' }, 'max', false), '22°', 'weather formats forecast metric highs')
assertEqual(weather.bareTempForDay({ maxtempC: '22', mintempC: '13', maxtempF: '72', mintempF: '55' }, 'min', true), '55°', 'weather formats forecast imperial lows')

assert(weather.dayIcon({ openMeteoWeatherCode: 95 }).length > 0, 'weather maps Open-Meteo weather icons')
assertEqual(weather.currentIcon({ openMeteoWeatherCode: 0, isDay: 1 }, ''), weather.iconForOpenMeteoCode(0), 'weather uses the current Open-Meteo icon with current values')
assertEqual(weather.currentIcon({ openMeteoWeatherCode: 0, isDay: 0 }, ''), weather.iconForCode(113, true), 'weather uses the nighttime Open-Meteo icon after sunset')
assert(weather.iconForOpenMeteoCode(45, true) !== weather.iconForOpenMeteoCode(45, false), 'weather distinguishes nighttime fog from daytime fog')
assert(weather.iconForCode(248, true) !== weather.iconForCode(248, false), 'weather distinguishes nighttime fog from daytime fog by wttr code')
assertEqual(weather.provisionalCurrentIcon({ weatherCode: 113 }, ''), weather.iconForCode(113, false), 'weather uses wttr to fill an empty initial icon')
assertEqual(weather.provisionalCurrentIcon({ weatherCode: 113 }, 'night'), 'night', 'weather refresh preserves a resolved day-night icon')
// The bar identifies a panel by the widget in its slot, so the nested panel
// has to present the host widget rather than itself — otherwise the
// open-panel dot never lights and Tab cannot leave the panel.
assert(
  panelSource.includes('owner: root.barIdentity'),
  'weather panel gives the bar its host widget as popout identity'
)
assert(
  panelSource.includes('switchPanelFrom(root.barIdentity, direction)'),
  'weather panel switches panels as its host widget'
)
assert(
  widgetSource.includes('target.hostWidget = root'),
  'weather widget injects itself as the panel host'
)
assert(
  widgetSource.includes('readonly property bool popoutSwitchClosing:') && widgetSource.includes('function closeForPopoutSwitch()'),
  'weather widget forwards the popout-switch handshake'
)
assert(
  /Qt\.callLater\(function\(\) \{\s*\n\s*if \(root\.opened\) setCenterHoverRevealSuppressed\(true\)/.test(panelSource),
  'weather claims the shared hover-reveal flag after the popout handoff, so the panel taking over wins'
)

assert(
  panelSource.includes('text: root.label || "—"'),
  'weather hero and bar use the same resolved icon'
)
assert(
  panelSource.includes('onReturnRequested: root.startEditingLocation()'),
  'weather focuses city input when Return is pressed'
)
assert(
  panelSource.split('root.controller.show()\n    locationFile.reload()\n    root.refresh()').length === 3,
  'weather reloads external location changes whenever either open path runs'
)
assert(!weather.weatherResponseCompletesSave(true, 'wttr'), 'weather keeps the spinner through a non-authoritative pinned-location response')
assert(weather.weatherResponseCompletesSave(true, 'open-meteo'), 'weather completes a pinned-location save with Open-Meteo data')
assert(weather.weatherResponseCompletesSave(false, 'wttr'), 'weather completes a name-only location save with wttr data')
assertEqual(
  weather.dayIcon({ hourly: [{ time: '900', weatherCode: 113 }, { time: '1200', weatherCode: 389 }, { time: '1800', weatherCode: 116 }] }),
  weather.iconForCode(389, false),
  'weather picks hourly forecast icon nearest noon'
)
JS

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

weather_location() {
  HOME="$test_tmp" "$ROOT/bin/omarchy-weather-location" "$@"
}

weather_location --set "Malibu" "34.02577,-118.7804"
[[ $(jq -c . "$test_tmp/.local/state/omarchy/settings/weather.json") == '{"name":"Malibu","latitude":34.02577,"longitude":-118.7804}' ]] || fail "weather location stores name and coordinates as JSON"
pass "weather location stores name and coordinates as JSON"

[[ $(weather_location) == "Malibu" ]] || fail "weather location returns the stored name"
pass "weather location returns the stored name"

weather_location --set "New York"
[[ $(jq -c . "$test_tmp/.local/state/omarchy/settings/weather.json") == '{"name":"New York"}' ]] || fail "weather location stores a bare name as JSON"
[[ $(weather_location) == "New York" ]] || fail "weather location returns a bare stored name"
pass "weather location stores and returns a bare name"

if weather_location --set "bad" "not,coords" 2>/dev/null; then
  fail "weather location rejects malformed coordinates"
fi
pass "weather location rejects malformed coordinates"

weather_location --clear
[[ ! -e "$test_tmp/.local/state/omarchy/settings/weather.json" ]] || fail "weather location clear removes the state file"
pass "weather location clear removes the state file"

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

# wttr.in's j1 payload, cut down to the three fields omarchy-weather-icon reads.
cat >"$stub_bin/curl" <<'SH'
#!/bin/bash

jq -n --arg code "$OMARCHY_TEST_WEATHER_CODE" '{
  current_condition: [{ weatherCode: $code }],
  weather: [{ astronomy: [{ sunrise: "6:00 AM", sunset: "8:00 PM" }] }]
}'
SH

# A fixed clock, so which side of sunset a run lands on is decided here rather
# than by whenever the suite happens to be running. Seconds into the day stand
# in for epochs: the script only compares the three values against each other.
cat >"$stub_bin/date" <<'SH'
#!/bin/bash

if [[ ${1:-} == "-d" ]]; then
  case "$2" in
  "today 6:00 AM") printf '%s\n' 21600 ;;
  "today 8:00 PM") printf '%s\n' 72000 ;;
  *) exit 1 ;;
  esac
  exit 0
fi

printf '%s\n' "$OMARCHY_TEST_NOW"
SH

chmod +x "$stub_bin/curl" "$stub_bin/date"

weather_icon() {
  PATH="$stub_bin:$PATH" HOME="$test_tmp" OMARCHY_TEST_NOW="$1" OMARCHY_TEST_WEATHER_CODE="$2" \
    "$ROOT/bin/omarchy-weather-icon"
}

# The panel resolves the same wttr code through Model.iconForCode, so ask that
# mapping for the expected glyph instead of pinning a second copy of it here.
model_icon() {
  node -e '
    const model = require(process.env.ROOT + "/shell/plugins/panels/weather/Model.js")
    process.stdout.write(model.iconForCode(Number(process.argv[1]), process.argv[2] === "night"))
  ' "$1" "$2"
}

# One code from every arm of the case statement, all three fog codes, and one
# the mapping does not know so the fallback is covered too.
icon_mismatches() {
  local phase=$1 now=$2 code actual expected mismatches=""

  for code in 113 116 119 122 143 176 179 182 200 248 260 266 329 999; do
    actual=$(weather_icon "$now" "$code")
    expected=$(model_icon "$code" "$phase")
    [[ $actual == "$expected" ]] || mismatches+="code $code: $actual != $expected"$'\n'
  done

  printf '%s' "$mismatches"
}

mismatched=$(icon_mismatches day 43200)
[[ -z $mismatched ]] || fail "weather icon matches the panel's daytime glyphs" "$mismatched"
pass "weather icon matches the panel's daytime glyphs"

mismatched=$(icon_mismatches night 79200)
[[ -z $mismatched ]] || fail "weather icon matches the panel's nighttime glyphs" "$mismatched"
pass "weather icon matches the panel's nighttime glyphs"
