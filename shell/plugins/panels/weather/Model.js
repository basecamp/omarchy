// weather.json holds {"name": ..., "latitude": ..., "longitude": ...} (see
// omarchy-weather-location, which owns the format). Missing, blank, or
// unparseable means the location is auto-detected from the IP address.
function parseLocationFile(raw) {
  var unset = { name: "", latitude: null, longitude: null }
  try {
    var data = JSON.parse(String(raw || ""))
    if (!data || typeof data !== "object") return unset

    var latitude = parseFloat(data.latitude)
    var longitude = parseFloat(data.longitude)
    var hasCoordinates = !isNaN(latitude) && !isNaN(longitude)
    return {
      name: typeof data.name === "string" ? data.name.replace(/^\s+|\s+$/g, "") : "",
      latitude: hasCoordinates ? latitude : null,
      longitude: hasCoordinates ? longitude : null
    }
  } catch (e) {
    return unset
  }
}

// wttr.in path segment for a configured location: exact coordinates when
// both are present, the URL-encoded name as a fallback (hand-edited
// weather.loc files may only carry a name), empty for IP auto-detect.
function wttrLocationQuery(location, latitude, longitude) {
  var lat = parseFloat(String(latitude))
  var lon = parseFloat(String(longitude))
  if (!isNaN(lat) && !isNaN(lon)) return lat + "," + lon

  var name = String(location || "").replace(/^\s+|\s+$/g, "")
  return name === "" ? "" : encodeURIComponent(name)
}

// Open-Meteo geocoding response → suggestion rows for the location picker.
function parseGeocodingResults(raw) {
  try {
    var data = JSON.parse(String(raw || "{}"))
    var results = data.results
    if (!results || !results.length) return []

    var out = []
    for (var i = 0; i < results.length; i++) {
      var r = results[i]
      if (!r || !r.name || r.latitude === undefined || r.longitude === undefined) continue
      var region = [r.admin1, r.country].filter(function(part) { return !!part }).join(", ")
      out.push({
        name: String(r.name),
        description: region,
        latitude: r.latitude,
        longitude: r.longitude
      })
    }
    return out
  } catch (e) {
    return []
  }
}

function locationCommit(text, suggestions, selectedIndex) {
  var name = String(text || "").replace(/^\s+|\s+$/g, "")
  if (name === "") return { name: "", latitude: null, longitude: null }

  var choices = suggestions || []
  var index = Math.max(0, Math.min(parseInt(selectedIndex, 10) || 0, choices.length - 1))
  var suggestion = choices[index]
  if (suggestion) return suggestion

  return { name: name, latitude: null, longitude: null }
}

function isFutureForecastDate(dateString, todayString) {
  if (!dateString) return false
  return String(dateString).slice(0, 10) > String(todayString || "")
}

function roundedTemp(value) {
  if (value === undefined || value === null || value === "") return ""
  var n = parseFloat(String(value))
  return isNaN(n) ? "" : String(Math.round(n))
}

function celsiusToFahrenheit(value) {
  if (value === undefined || value === null || value === "") return ""
  var n = parseFloat(String(value))
  return isNaN(n) ? "" : (n * 9 / 5) + 32
}

function fahrenheitToCelsius(value) {
  if (value === undefined || value === null || value === "") return ""
  var n = parseFloat(String(value))
  return isNaN(n) ? "" : (n - 32) * 5 / 9
}

function formatTemp(value, useImperial) {
  if (value === undefined || value === null || value === "") return ""
  return value + "°" + (useImperial ? "F" : "C")
}

function normalizedUnit(value) {
  return String(value || "").replace(/^\s+|\s+$/g, "").toLowerCase()
}

function localeUsesImperial(localeName) {
  var name = String(localeName || "").replace(".", "_")
  return /^en[_-]US($|[_.-])/.test(name) || /^en[_-]LR($|[_.-])/.test(name) || /^my($|[_.-])/.test(name)
}

function countryUsesImperial(countryName) {
  var country = String(countryName || "")
    .replace(/^\s+|\s+$/g, "")
    .replace(/[._-]+/g, " ")
    .toLowerCase()
  if (!country) return null
  if (country === "us" || country === "usa" || country === "united states" || country === "united states of america") return true
  if (country === "liberia" || country === "myanmar" || country === "burma") return true
  return false
}

function shouldUseImperial(unitOverride, localeName, countryName) {
  var unit = normalizedUnit(unitOverride)
  if (unit === "imperial") return true
  if (unit === "metric") return false

  var countryPreference = countryUsesImperial(countryName)
  if (countryPreference !== null) return countryPreference

  return localeUsesImperial(localeName)
}

// Forecast sources the panel can switch between. Open-Meteo remains the
// default: no API key, global coverage, one request for current + daily.
// The other Open-Meteo entries pin a model. NWS is the US official forecast
// (what Apple Weather tracks). wttr.in is the original lookup service.
var WEATHER_PROVIDERS = [
  { id: "open-meteo", label: "Open-Meteo", kind: "open-meteo", model: "" },
  { id: "nws", label: "National Weather Service", kind: "nws", model: "" },
  { id: "nbm", label: "NOAA National Blend", kind: "open-meteo", model: "ncep_nbm_conus" },
  { id: "gfs", label: "NOAA GFS", kind: "open-meteo", model: "gfs_seamless" },
  { id: "ecmwf", label: "ECMWF", kind: "open-meteo", model: "ecmwf_ifs025" },
  { id: "icon", label: "DWD ICON", kind: "open-meteo", model: "icon_seamless" },
  { id: "wttr", label: "wttr.in", kind: "wttr", model: "" }
]

function providerCatalog() {
  return WEATHER_PROVIDERS
}

function providerOptions() {
  var out = []
  for (var i = 0; i < WEATHER_PROVIDERS.length; i++) {
    out.push({ value: WEATHER_PROVIDERS[i].id, label: WEATHER_PROVIDERS[i].label })
  }
  return out
}

function normalizedProvider(value) {
  var id = String(value || "").replace(/^\s+|\s+$/g, "").toLowerCase()
  for (var i = 0; i < WEATHER_PROVIDERS.length; i++) {
    if (WEATHER_PROVIDERS[i].id === id) return id
  }
  return "open-meteo"
}

function providerInfo(value) {
  var id = normalizedProvider(value)
  for (var i = 0; i < WEATHER_PROVIDERS.length; i++) {
    if (WEATHER_PROVIDERS[i].id === id) return WEATHER_PROVIDERS[i]
  }
  return WEATHER_PROVIDERS[0]
}

function shellQuote(value) {
  return "'" + String(value).replace(/'/g, "'\\''") + "'"
}

function openMeteoForecastUrl(lat, lon, model) {
  var url = "https://api.open-meteo.com/v1/forecast"
    + "?latitude=" + encodeURIComponent(String(lat))
    + "&longitude=" + encodeURIComponent(String(lon))
    + "&daily=weather_code,temperature_2m_max,temperature_2m_min"
    + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day"
    + "&forecast_days=4"
    + "&timezone=auto"
  var pinned = String(model || "")
  if (pinned) url += "&models=" + encodeURIComponent(pinned)
  return url
}

function nwsUserAgent() {
  return "Omarchy weather (+https://github.com/basecamp/omarchy)"
}

function nwsPointsUrl(lat, lon) {
  return "https://api.weather.gov/points/" + encodeURIComponent(String(lat)) + "," + encodeURIComponent(String(lon))
}

// One bash process: points -> forecast + latest observation. weather.gov
// requires an identifying User-Agent; observation is best-effort so a
// missing station still yields the daily forecast.
function nwsFetchCommand(lat, lon) {
  var ua = nwsUserAgent()
  var script = "set -euo pipefail\n"
    + "ua=" + shellQuote(ua) + "\n"
    + "points=$(curl -fsS -A \"$ua\" --max-time 6 " + shellQuote(nwsPointsUrl(lat, lon)) + ")\n"
    + "forecast_url=$(jq -er .properties.forecast <<<\"$points\")\n"
    + "forecast=$(curl -fsS -A \"$ua\" --max-time 6 \"$forecast_url\")\n"
    + "obs='{}'\n"
    + "stations_url=$(jq -r '.properties.observationStations // empty' <<<\"$points\" || true)\n"
    + "if [[ -n $stations_url ]]; then\n"
    + "  station=$(curl -fsS -A \"$ua\" --max-time 6 \"$stations_url\" | jq -r '.observationStations[0] // empty' || true)\n"
    + "  if [[ -n $station ]]; then\n"
    + "    obs=$(curl -fsS -A \"$ua\" --max-time 6 \"$station/observations/latest\" || printf '%s' '{}')\n"
    + "  fi\n"
    + "fi\n"
    + "jq -nc --argjson forecast \"$forecast\" --argjson observation \"$obs\" '{forecast:$forecast,observation:$observation}'\n"
  return ["bash", "-c", script]
}

function nwsQuantity(value) {
  if (value === undefined || value === null || value === "") return null
  if (typeof value === "number") return value
  if (typeof value === "object" && value.value !== undefined && value.value !== null && value.value !== "") {
    var n = parseFloat(String(value.value))
    return isNaN(n) ? null : n
  }
  var parsed = parseFloat(String(value))
  return isNaN(parsed) ? null : parsed
}

function nwsTemps(value, unit) {
  var n = parseFloat(String(value))
  if (isNaN(n)) return { c: "", f: "" }
  var isF = !unit || String(unit).toUpperCase() === "F"
  if (isF) return { c: roundedTemp(fahrenheitToCelsius(n)), f: roundedTemp(n) }
  return { c: roundedTemp(n), f: roundedTemp(celsiusToFahrenheit(n)) }
}

function nwsWindMph(text) {
  var matches = String(text || "").match(/(\d+(?:\.\d+)?)/g)
  if (!matches || !matches.length) return ""
  return parseFloat(matches[matches.length - 1])
}

function iconCodeFromNwsText(text) {
  var t = String(text || "").toLowerCase()
  if (!t) return 3
  if (t.indexOf("thunder") !== -1) return 95
  if (t.indexOf("snow") !== -1 || t.indexOf("sleet") !== -1 || t.indexOf("blizzard") !== -1) return 71
  if (t.indexOf("freezing") !== -1 || t.indexOf("ice") !== -1) return 71
  if (t.indexOf("rain") !== -1 || t.indexOf("shower") !== -1 || t.indexOf("drizzle") !== -1) return 63
  if (t.indexOf("fog") !== -1 || t.indexOf("mist") !== -1 || t.indexOf("haze") !== -1) return 45
  if (t.indexOf("overcast") !== -1) return 3
  if (t.indexOf("cloud") !== -1 && t.indexOf("partly") === -1 && t.indexOf("mostly sunny") === -1 && t.indexOf("mostly clear") === -1) return 3
  if (t.indexOf("partly") !== -1 || t.indexOf("mostly sunny") !== -1 || t.indexOf("mostly clear") !== -1) return 2
  if (t.indexOf("sunny") !== -1 || t.indexOf("clear") !== -1 || t.indexOf("fair") !== -1) return 0
  return 3
}

function nwsPeriodIsDay(period) {
  if (!period || period.isDaytime === undefined || period.isDaytime === null) return 1
  return period.isDaytime ? 1 : 0
}

function nwsObservationCondition(observation, isDay) {
  var props = observation && observation.properties ? observation.properties : null
  if (!props) return null
  var tempC = nwsQuantity(props.temperature)
  if (tempC === null) return null
  var feelsC = nwsQuantity(props.heatIndex)
  if (feelsC === null) feelsC = nwsQuantity(props.windChill)
  if (feelsC === null) feelsC = tempC
  var windKmh = nwsQuantity(props.windSpeed)
  if (windKmh === null) windKmh = 0
  var humidity = nwsQuantity(props.relativeHumidity)
  return {
    temp_C: roundedTemp(tempC),
    temp_F: roundedTemp(celsiusToFahrenheit(tempC)),
    FeelsLikeC: roundedTemp(feelsC),
    FeelsLikeF: roundedTemp(celsiusToFahrenheit(feelsC)),
    windspeedKmph: roundedTemp(windKmh),
    windspeedMiles: roundedTemp(windKmh * 0.621371),
    humidity: humidity === null ? "" : roundedTemp(humidity),
    openMeteoWeatherCode: iconCodeFromNwsText(props.textDescription),
    isDay: Number(isDay) === 0 ? 0 : 1
  }
}

function nwsPeriodCondition(period) {
  if (!period || period.temperature === undefined || period.temperature === null) return null
  var temps = nwsTemps(period.temperature, period.temperatureUnit)
  var mph = nwsWindMph(period.windSpeed)
  var kmh = mph === "" ? 0 : mph * 1.60934
  return {
    temp_C: temps.c,
    temp_F: temps.f,
    FeelsLikeC: temps.c,
    FeelsLikeF: temps.f,
    windspeedKmph: roundedTemp(kmh),
    windspeedMiles: roundedTemp(mph === "" ? 0 : mph),
    humidity: "",
    openMeteoWeatherCode: iconCodeFromNwsText(period.shortForecast),
    isDay: period.isDaytime ? 1 : 0
  }
}

function nwsCurrentCondition(nwsReport) {
  var periods = nwsReport && nwsReport.forecast && nwsReport.forecast.properties
    ? nwsReport.forecast.properties.periods : []
  var period = periods && periods[0] ? periods[0] : null
  var fromObs = nwsObservationCondition(nwsReport && nwsReport.observation, nwsPeriodIsDay(period))
  if (fromObs) return fromObs
  return nwsPeriodCondition(period)
}

function nwsForecastDays(nwsReport, todayString) {
  var forecast = nwsReport && nwsReport.forecast ? nwsReport.forecast : nwsReport
  var periods = forecast && forecast.properties && forecast.properties.periods ? forecast.properties.periods : []
  if (!periods.length) return []

  var byDate = {}
  var order = []
  for (var i = 0; i < periods.length; i++) {
    var period = periods[i]
    if (!period || !period.startTime) continue
    var date = String(period.startTime).slice(0, 10)
    if (!byDate[date]) {
      byDate[date] = { date: date, day: null, night: null }
      order.push(date)
    }
    if (period.isDaytime) byDate[date].day = period
    else byDate[date].night = period
  }

  var result = []
  for (var j = 0; j < order.length && result.length < 3; j++) {
    var day = byDate[order[j]]
    if (!isFutureForecastDate(day.date, todayString)) continue
    var highPeriod = day.day || day.night
    var lowPeriod = day.night || day.day
    if (!highPeriod) continue
    var high = nwsTemps(highPeriod.temperature, highPeriod.temperatureUnit)
    var low = nwsTemps(lowPeriod.temperature, lowPeriod.temperatureUnit)
    result.push({
      date: day.date,
      maxtempC: high.c,
      mintempC: low.c,
      maxtempF: high.f,
      mintempF: low.f,
      openMeteoWeatherCode: iconCodeFromNwsText(highPeriod.shortForecast)
    })
  }
  return result
}

function currentCondition(hasConfiguredCoordinates, openMeteoCurrent, wttrCurrent, nwsCurrent, providerId) {
  var kind = providerInfo(providerId).kind
  if (kind === "nws") return nwsCurrent || null
  if (kind === "wttr") return wttrCurrent || null
  if (hasConfiguredCoordinates && openMeteoCurrent) return openMeteoCurrent
  return wttrCurrent || openMeteoCurrent || null
}

function dayName(dateString, formatter) {
  if (!dateString) return ""
  var d = new Date(dateString + "T12:00:00")
  if (isNaN(d.getTime())) return ""
  if (formatter) return formatter(d)
  return ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][d.getDay()]
}

function openMeteoForecastDays(dailyForecastReport, todayString) {
  var daily = dailyForecastReport && dailyForecastReport.daily ? dailyForecastReport.daily : null
  if (!daily || !daily.time) return []

  var result = []
  for (var i = 0; i < daily.time.length && result.length < 3; ++i) {
    var date = daily.time[i]
    if (!isFutureForecastDate(date, todayString)) continue

    var maxC = daily.temperature_2m_max ? daily.temperature_2m_max[i] : ""
    var minC = daily.temperature_2m_min ? daily.temperature_2m_min[i] : ""
    result.push({
      date: date,
      maxtempC: roundedTemp(maxC),
      mintempC: roundedTemp(minC),
      maxtempF: roundedTemp(celsiusToFahrenheit(maxC)),
      mintempF: roundedTemp(celsiusToFahrenheit(minC)),
      openMeteoWeatherCode: daily.weather_code ? daily.weather_code[i] : null
    })
  }
  return result
}

// Open-Meteo bundles current conditions with the daily forecast request and
// answers far faster than wttr.in. Normalize them to wttr's
// current_condition shape so the panel can use either source
// interchangeably. Open-Meteo reports metric (°C, km/h).
function openMeteoCurrentCondition(dailyForecastReport) {
  var current = dailyForecastReport && dailyForecastReport.current ? dailyForecastReport.current : null
  if (!current || current.temperature_2m === undefined || current.temperature_2m === null) return null
  return {
    temp_C: roundedTemp(current.temperature_2m),
    temp_F: roundedTemp(celsiusToFahrenheit(current.temperature_2m)),
    FeelsLikeC: roundedTemp(current.apparent_temperature),
    FeelsLikeF: roundedTemp(celsiusToFahrenheit(current.apparent_temperature)),
    windspeedKmph: roundedTemp(current.wind_speed_10m),
    windspeedMiles: roundedTemp(current.wind_speed_10m * 0.621371),
    humidity: roundedTemp(current.relative_humidity_2m),
    openMeteoWeatherCode: current.weather_code,
    isDay: current.is_day
  }
}

function currentIcon(current, fallback) {
  if (!current) return fallback || ""
  if (current.openMeteoWeatherCode !== undefined && current.openMeteoWeatherCode !== null)
    return iconForOpenMeteoCode(current.openMeteoWeatherCode, Number(current.isDay) === 0)
  if (current.weatherCode !== undefined && current.weatherCode !== null)
    return iconForCode(current.weatherCode, false)
  return fallback || ""
}

// wttr.in has no day/night flag. Use its icon only to fill an empty initial
// state, never to replace a day/night-aware icon resolved by Open-Meteo.
function provisionalCurrentIcon(current, resolvedIcon) {
  return resolvedIcon || currentIcon(current, "")
}

function weatherResponseCompletesSave(hasConfiguredCoordinates, source, providerId) {
  var kind = providerInfo(providerId).kind
  if (kind === "nws") return source === "nws"
  if (kind === "wttr") return source === "wttr"
  return hasConfiguredCoordinates ? source === "open-meteo" : source === "wttr"
}

function wttrNextForecastDays(report, todayString) {
  var days = report && report.weather ? report.weather : []
  var result = []
  for (var i = 0; i < days.length && result.length < 3; ++i) {
    if (isFutureForecastDate(days[i].date, todayString)) result.push(days[i])
  }
  return result
}

function buildForecastDays(report, dailyForecastReport, todayString, nwsReport, providerId) {
  var kind = providerInfo(providerId).kind
  if (kind === "nws") return nwsForecastDays(nwsReport, todayString)
  if (kind === "wttr") return wttrNextForecastDays(report, todayString)
  var days = openMeteoForecastDays(dailyForecastReport, todayString)
  return days.length > 0 ? days : wttrNextForecastDays(report, todayString)
}

function bareTempForDay(day, kind, useImperial) {
  if (!day) return ""
  var v = useImperial
    ? (kind === "max" ? day.maxtempF : day.mintempF)
    : (kind === "max" ? day.maxtempC : day.mintempC)
  if (v === undefined || v === null || v === "") return ""
  return v + "°"
}

function dayIcon(day) {
  if (!day) return ""
  if (day.openMeteoWeatherCode !== undefined && day.openMeteoWeatherCode !== null)
    return iconForOpenMeteoCode(day.openMeteoWeatherCode)
  if (!day.hourly || day.hourly.length === 0) return ""

  var best = day.hourly[0]
  var bestDist = 9999
  for (var i = 0; i < day.hourly.length; ++i) {
    var t = parseInt(String(day.hourly[i].time || "0"), 10)
    var dist = Math.abs(t - 1200)
    if (dist < bestDist) {
      bestDist = dist
      best = day.hourly[i]
    }
  }
  return iconForCode(best.weatherCode, false)
}

function iconForOpenMeteoCode(code, night) {
  var c = parseInt(String(code || "0"), 10)
  if (c === 0) return iconForCode(113, night)
  if (c === 1 || c === 2) return iconForCode(116, night)
  if (c === 3) return iconForCode(119, night)
  if (c === 45 || c === 48) return iconForCode(143, night)
  if (c === 51 || c === 53 || c === 55 || c === 56 || c === 57 || c === 61) return iconForCode(266, night)
  if (c === 63 || c === 65 || c === 66 || c === 67 || c === 80 || c === 81 || c === 82) return iconForCode(308, night)
  if (c === 71 || c === 73 || c === 75 || c === 77 || c === 85 || c === 86) return iconForCode(338, night)
  if (c === 95 || c === 96 || c === 99) return iconForCode(389, night)
  return iconForCode(119, night)
}

function iconForCode(code, night) {
  var c = parseInt(String(code || "0"), 10)
  switch (c) {
    case 113: return night ? "" : ""
    case 116: return night ? "" : ""
    case 119: case 122: return ""
    case 143: case 248: case 260: return night ? "\ue346" : "\ue313"
    case 176: case 263: case 353: return night ? "" : ""
    case 179: case 227: case 230: case 323: case 326: case 368: return night ? "" : ""
    case 182: case 185: case 281: case 284: case 311: case 314:
    case 317: case 320: case 350: case 362: case 365: case 374: case 377: return ""
    case 200: case 386: case 389: case 392: case 395: return ""
    case 266: case 293: case 296: case 299: case 302: case 305: case 308: case 356: case 359: return ""
    case 329: case 332: case 335: case 338: case 371: return ""
    default: return ""
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    parseLocationFile: parseLocationFile,
    wttrLocationQuery: wttrLocationQuery,
    parseGeocodingResults: parseGeocodingResults,
    locationCommit: locationCommit,
    isFutureForecastDate: isFutureForecastDate,
    roundedTemp: roundedTemp,
    celsiusToFahrenheit: celsiusToFahrenheit,
    fahrenheitToCelsius: fahrenheitToCelsius,
    formatTemp: formatTemp,
    normalizedUnit: normalizedUnit,
    localeUsesImperial: localeUsesImperial,
    countryUsesImperial: countryUsesImperial,
    shouldUseImperial: shouldUseImperial,
    providerCatalog: providerCatalog,
    providerOptions: providerOptions,
    normalizedProvider: normalizedProvider,
    providerInfo: providerInfo,
    openMeteoForecastUrl: openMeteoForecastUrl,
    nwsUserAgent: nwsUserAgent,
    nwsPointsUrl: nwsPointsUrl,
    nwsFetchCommand: nwsFetchCommand,
    nwsQuantity: nwsQuantity,
    nwsTemps: nwsTemps,
    nwsWindMph: nwsWindMph,
    iconCodeFromNwsText: iconCodeFromNwsText,
    nwsPeriodIsDay: nwsPeriodIsDay,
    nwsObservationCondition: nwsObservationCondition,
    nwsCurrentCondition: nwsCurrentCondition,
    nwsForecastDays: nwsForecastDays,
    currentCondition: currentCondition,
    dayName: dayName,
    openMeteoForecastDays: openMeteoForecastDays,
    openMeteoCurrentCondition: openMeteoCurrentCondition,
    currentIcon: currentIcon,
    provisionalCurrentIcon: provisionalCurrentIcon,
    weatherResponseCompletesSave: weatherResponseCompletesSave,
    wttrNextForecastDays: wttrNextForecastDays,
    buildForecastDays: buildForecastDays,
    bareTempForDay: bareTempForDay,
    dayIcon: dayIcon,
    iconForOpenMeteoCode: iconForOpenMeteoCode,
    iconForCode: iconForCode
  }
}
