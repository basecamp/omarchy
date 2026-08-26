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

assertEqual(weather.normalizedProvider(''), 'open-meteo', 'weather defaults an empty provider to Open-Meteo')
assertEqual(weather.normalizedProvider('NWS'), 'nws', 'weather normalizes provider ids')
assertEqual(weather.normalizedProvider('nope'), 'open-meteo', 'weather falls back from unknown providers')
assertEqual(weather.providerInfo('nbm').model, 'ncep_nbm_conus', 'weather maps NOAA National Blend to the Open-Meteo NBM model')
assertEqual(weather.providerInfo('gfs').kind, 'open-meteo', 'weather treats GFS as an Open-Meteo model pin')
assertEqual(weather.providerInfo('nws').kind, 'nws', 'weather treats NWS as its own provider')
assertEqual(weather.providerOptions().map(o => o.value).join(','), 'open-meteo,nws,nbm,gfs,ecmwf,icon,wttr', 'weather lists every forecast provider')

assertEqual(
  weather.openMeteoForecastUrl(36.023, -95.968, ''),
  'https://api.open-meteo.com/v1/forecast?latitude=36.023&longitude=-95.968&daily=weather_code,temperature_2m_max,temperature_2m_min&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day&forecast_days=4&timezone=auto',
  'weather Open-Meteo URL omits models for the default provider'
)
assert(
  weather.openMeteoForecastUrl(36.023, -95.968, 'ncep_nbm_conus').endsWith('&models=ncep_nbm_conus'),
  'weather Open-Meteo URL pins a selected model'
)

const nwsCommand = weather.nwsFetchCommand(36.023, -95.968)
assertEqual(nwsCommand[0], 'bash', 'weather NWS fetch runs through bash')
assert(nwsCommand[2].includes('api.weather.gov/points/36.023,-95.968'), 'weather NWS fetch starts at the points API')
assert(nwsCommand[2].includes(weather.nwsUserAgent()), 'weather NWS fetch sends an identifying User-Agent')
assert(
  nwsCommand[2].includes(".observationStations[0] // empty' || true"),
  'weather NWS station lookup is best-effort so a failed observation still yields the forecast'
)

const nwsForecast = {
  forecast: {
    properties: {
      periods: [
        { name: 'Today', startTime: '2026-08-26T09:00:00-05:00', isDaytime: true, temperature: 95, temperatureUnit: 'F', shortForecast: 'Partly Sunny' },
        { name: 'Tonight', startTime: '2026-08-26T18:00:00-05:00', isDaytime: false, temperature: 72, temperatureUnit: 'F', shortForecast: 'Mostly Clear' },
        { name: 'Thursday', startTime: '2026-08-27T06:00:00-05:00', isDaytime: true, temperature: 94, temperatureUnit: 'F', shortForecast: 'Mostly Sunny' },
        { name: 'Thursday Night', startTime: '2026-08-27T18:00:00-05:00', isDaytime: false, temperature: 68, temperatureUnit: 'F', shortForecast: 'Mostly Clear' },
        { name: 'Friday', startTime: '2026-08-28T06:00:00-05:00', isDaytime: true, temperature: 94, temperatureUnit: 'F', shortForecast: 'Sunny' },
        { name: 'Friday Night', startTime: '2026-08-28T18:00:00-05:00', isDaytime: false, temperature: 70, temperatureUnit: 'F', shortForecast: 'Mostly Clear' },
        { name: 'Saturday', startTime: '2026-08-29T06:00:00-05:00', isDaytime: true, temperature: 97, temperatureUnit: 'F', shortForecast: 'Sunny' },
        { name: 'Saturday Night', startTime: '2026-08-29T18:00:00-05:00', isDaytime: false, temperature: 73, temperatureUnit: 'F', shortForecast: 'Mostly Clear' }
      ]
    }
  },
  observation: {
    properties: {
      temperature: { value: 29 },
      heatIndex: { value: 32.7 },
      windSpeed: { value: 14.832 },
      relativeHumidity: { value: 70.1 },
      textDescription: 'Clear'
    }
  }
}

assertDeepEqual(
  weather.nwsForecastDays(nwsForecast, '2026-08-26').map(day => ({ date: day.date, maxtempF: day.maxtempF, mintempF: day.mintempF })),
  [
    { date: '2026-08-27', maxtempF: '94', mintempF: '68' },
    { date: '2026-08-28', maxtempF: '94', mintempF: '70' },
    { date: '2026-08-29', maxtempF: '97', mintempF: '73' }
  ],
  'weather groups NWS day/night periods into future daily highs and lows'
)
assertDeepEqual(
  weather.nwsCurrentCondition(nwsForecast),
  { temp_C: '29', temp_F: '84', FeelsLikeC: '33', FeelsLikeF: '91', windspeedKmph: '15', windspeedMiles: '9', humidity: '70', openMeteoWeatherCode: 0, isDay: 1 },
  'weather normalizes NWS observations to the shared current-condition shape'
)
assertEqual(weather.nwsCurrentCondition({ forecast: nwsForecast.forecast }).temp_F, '95', 'weather falls back to the first NWS period without an observation')
assertEqual(weather.nwsPeriodIsDay({ isDaytime: false }), 0, 'weather reads nighttime from an NWS period')
assertEqual(
  weather.nwsCurrentCondition({
    forecast: { properties: { periods: [{ isDaytime: false, temperature: 72, temperatureUnit: 'F', shortForecast: 'Mostly Clear' }] } },
    observation: nwsForecast.observation
  }).isDay,
  0,
  'weather uses the current NWS period for observation day/night icons'
)
assertEqual(weather.iconCodeFromNwsText('Mostly Sunny'), 2, 'weather maps NWS partly-sunny text to a partly-cloudy icon')
assertEqual(weather.iconCodeFromNwsText('Thunderstorms'), 95, 'weather maps NWS thunder text to a storm icon')
assertEqual(weather.nwsWindMph('5 to 10 mph'), 10, 'weather reads the upper NWS wind range')

assertEqual(weather.buildForecastDays(wttr, {}, '2026-08-26', nwsForecast, 'nws')[0].maxtempF, '94', 'weather uses NWS days when that provider is selected')
assertEqual(weather.buildForecastDays(wttr, openMeteo, '2026-05-25', nwsForecast, 'wttr')[0].date, '2026-05-26', 'weather uses wttr days when that provider is selected')
assertEqual(weather.buildForecastDays(wttr, openMeteo, '2026-05-25', nwsForecast, 'open-meteo')[0].date, '2026-05-26', 'weather keeps Open-Meteo days for the default provider')
assertEqual(weather.currentCondition(true, { temp_F: '99' }, { temp_F: '78' }, { temp_F: '84' }, 'nws').temp_F, '84', 'weather current conditions follow the selected provider')
assertEqual(weather.currentCondition(true, { temp_F: '99' }, { temp_F: '78' }, { temp_F: '84' }, 'open-meteo').temp_F, '99', 'weather current conditions prefer Open-Meteo for a pinned location')

assert(weather.weatherResponseCompletesSave(true, 'nws', 'nws'), 'weather completes a pinned NWS location save with NWS data')
assert(!weather.weatherResponseCompletesSave(true, 'open-meteo', 'nws'), 'weather keeps the spinner through a non-NWS response when NWS is selected')
assert(weather.weatherResponseCompletesSave(true, 'wttr', 'wttr'), 'weather completes a wttr provider save with wttr data')

assert(panelSource.includes('text: "FORECAST"'), 'weather panel exposes a forecast provider dropdown')
assert(panelSource.includes('root.setProvider(v)'), 'weather panel persists the selected forecast provider')
assert(panelSource.includes('onWeatherProviderChanged:'), 'weather refetches when the provider setting changes')
assert(panelSource.includes('Model.openMeteoForecastUrl'), 'weather panel builds Open-Meteo URLs from the selected model')
assert(panelSource.includes('Model.nwsFetchCommand'), 'weather panel fetches NWS through the shared command builder')
assert(panelSource.includes('blocked: root.editingLocation || providerDropdown.popupOpen'), 'weather blocks panel keys while the provider dropdown is open')
assert(panelSource.includes('t === "f" || t === "F"'), 'weather opens the forecast dropdown from the f key')
assert(panelSource.includes('providerDropdown.toggle()'), 'weather toggles the forecast dropdown from the keyboard')
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
