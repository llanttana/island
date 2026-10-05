import QtQuick
import Quickshell
import Quickshell.Io

// One weather service for the whole island. The control center's temperature
// chip and the Weather page read the same numbers from here, so a location is
// asked about once and refreshed once, instead of once per view.
//
// Two sources, tried in order:
//
//   open-meteo  the primary. Takes the latitude and longitude Omarchy already
//               stores, needs no key and no account, and returns one clean JSON
//               document with the current hour and a daily forecast.
//   wttr.in     the fallback. Wordier and slower, but it is the source that
//               keeps working when Open-Meteo's free API host is unreachable,
//               which it is on some networks: the host resolves to a single
//               address that can be blocked outright.
//
// Whichever source answered last is tried first next time, so a host that is
// blocked costs one timeout rather than one on every refresh. The last good
// answer is cached on disk, and when both sources fail the island keeps showing
// what it last saw and raises `stale` instead of blanking the page.
Item {
  id: weather
  required property var host

  // "loading" until the first answer, then "ready", or "offline" when every
  // source failed and there is nothing cached to fall back on, or "nolocation"
  // when Omarchy has no location stored.
  property string state: "loading"
  property string place: ""
  property bool hasLocation: false
  // True while the numbers on screen come from the cache after a failed fetch.
  property bool stale: false
  property double lat: 0
  property double lon: 0
  property double fetchedAt: 0
  // Which source produced what is on screen, and which one is in flight.
  property string lastGoodSource: ""
  property string pendingSource: ""
  property int tried: 0

  // { tempC, feelsC, humidity, windKmh, code, isDay }. `code` is a WMO code
  // whatever the source was, so the icons and the wording live in one place.
  property var current: null
  // [{ date, code, maxC, minC }], today first.
  property var days: []

  readonly property var sources: ["open-meteo", "wttr.in"]
  readonly property bool loading: fetch.running
  readonly property string cachePath: host.home + "/.cache/omarchy/island-weather.json"
  // A quarter of an hour is plenty for a chip, and these are free services
  // worth being polite to.
  readonly property int maxAgeMs: 900000
  // Short, because a blocked host is a real possibility and the fallback should
  // not have to wait long to be tried.
  readonly property int fetchTimeout: 6

  // ---------- The location Omarchy already keeps ----------

  FileView {
    id: locationFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/weather.json"
    watchChanges: true
    printErrors: false
    onLoaded: weather.readLocation(text())
    onFileChanged: reload()
    onLoadFailed: function(error) {
      if (error !== FileViewError.FileNotFound) return
      weather.hasLocation = false
      if (weather.state === "loading") weather.state = "nolocation"
    }
  }

  function readLocation(raw) {
    var d
    try { d = JSON.parse(raw || "{}") } catch (e) { return }
    if (d.latitude === undefined || d.longitude === undefined) {
      weather.hasLocation = false
      weather.place = String(d.name || "")
      if (weather.state === "loading") weather.state = "nolocation"
      return
    }
    weather.lat = Number(d.latitude)
    weather.lon = Number(d.longitude)
    weather.hasLocation = true
    if (d.name) weather.place = String(d.name)
    weather.refresh()
  }

  // ---------- Cache ----------
  //
  // The whole answer, plus when it landed and which source produced it, so a
  // restart shows the weather immediately, skips the network while the answer
  // is fresh, and knows which source to ask first.

  FileView {
    id: cacheFile
    path: weather.cachePath
    atomicWrites: true
    printErrors: false
    onLoaded: weather.applyCache(text())
    onLoadFailed: function(error) {
      if (error !== FileViewError.FileNotFound) return
    }
  }

  function applyCache(raw) {
    if (weather.fetchedAt > 0) return          // a live answer already landed
    var doc
    try { doc = JSON.parse(raw || "") } catch (e) { return }
    if (!doc || !doc.current) return
    weather.current = doc.current
    weather.days = Array.isArray(doc.days) ? doc.days : []
    weather.fetchedAt = Number(doc.fetchedAt) || 0
    weather.lastGoodSource = String(doc.source || "")
    if (!weather.place && doc.place) weather.place = String(doc.place)
    // Not `stale`: serving a fresh cache without going to the network is the
    // normal path, not a failure. `stale` means a fetch was tried and failed.
    weather.state = "ready"
  }

  function saveCache() {
    cacheFile.setText(JSON.stringify({
      fetchedAt: weather.fetchedAt,
      source: weather.lastGoodSource,
      place: weather.place,
      current: weather.current,
      days: weather.days
    }) + "\n")
  }

  // ---------- Fetch ----------

  Process {
    id: fetch
    // Held across the two signals: the collector finishes before the process
    // exits, so the payload is whole by the time the exit code is judged.
    property string payload: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: fetch.payload = String(text || "")
    }
    onExited: function(code) {
      var body = fetch.payload
      fetch.payload = ""
      if (code !== 0 || body === "") weather.fetchFailed()
      else weather.applyAnswer(body)
    }
  }

  function sourceUrl(name) {
    if (name === "wttr.in")
      return "https://wttr.in/" + weather.lat + "," + weather.lon + "?format=j1"
    return "https://api.open-meteo.com/v1/forecast"
      + "?latitude=" + weather.lat + "&longitude=" + weather.lon
      + "&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m"
      + "&daily=weather_code,temperature_2m_max,temperature_2m_min"
      + "&timezone=auto&forecast_days=3"
  }

  function startFetch(name) {
    weather.pendingSource = name
    if (!weather.current) weather.state = "loading"
    fetch.command = ["curl", "-fsS", "--max-time", String(weather.fetchTimeout), weather.sourceUrl(name)]
    fetch.running = true
  }

  // Views call this when they open. Cheap when the answer is fresh, and it never
  // starts a second request while one is in flight.
  function refresh(force) {
    if (!weather.hasLocation || fetch.running) return
    if (!force && weather.fetchedAt > 0 && Date.now() - weather.fetchedAt < weather.maxAgeMs) return
    weather.tried = 0
    weather.startFetch(weather.lastGoodSource !== "" ? weather.lastGoodSource : weather.sources[0])
  }

  function fetchFailed() {
    // One source down is not the end: try the other before giving up on the
    // network. Deferred, because this runs inside the exit handler and the
    // process has to settle before it can be started again.
    weather.tried++
    if (weather.tried < weather.sources.length) {
      var other = weather.pendingSource === weather.sources[0] ? weather.sources[1] : weather.sources[0]
      Qt.callLater(function() { weather.startFetch(other) })
      return
    }
    // A cached answer beats an empty page, so keep what is on screen and only
    // call it offline when there is nothing at all.
    if (weather.current) { weather.stale = true; weather.state = "ready" }
    else weather.state = "offline"
  }

  function applyAnswer(raw) {
    var doc
    try { doc = JSON.parse(raw) } catch (e) { weather.fetchFailed(); return }
    var ok = weather.pendingSource === "wttr.in" ? weather.applyWttr(doc) : weather.applyOpenMeteo(doc)
    if (!ok) { weather.fetchFailed(); return }
    weather.fetchedAt = Date.now()
    weather.stale = false
    weather.state = "ready"
    weather.lastGoodSource = weather.pendingSource
    weather.saveCache()
  }

  // ---------- Parsers, both into the same shape ----------

  function applyOpenMeteo(doc) {
    var c = doc.current
    if (!c) return false
    weather.current = {
      tempC: Math.round(Number(c.temperature_2m)),
      feelsC: Math.round(Number(c.apparent_temperature)),
      humidity: Math.round(Number(c.relative_humidity_2m)),
      windKmh: Math.round(Number(c.wind_speed_10m)),
      code: Number(c.weather_code),
      isDay: Number(c.is_day) === 1
    }
    var daily = doc.daily || {}
    var times = Array.isArray(daily.time) ? daily.time : []
    var codes = Array.isArray(daily.weather_code) ? daily.weather_code : []
    var highs = Array.isArray(daily.temperature_2m_max) ? daily.temperature_2m_max : []
    var lows = Array.isArray(daily.temperature_2m_min) ? daily.temperature_2m_min : []
    var out = []
    for (var i = 0; i < times.length && out.length < 3; i++) {
      out.push({
        date: String(times[i]),
        code: Number(codes[i]),
        maxC: Math.round(Number(highs[i])),
        minC: Math.round(Number(lows[i]))
      })
    }
    weather.days = out
    return true
  }

  function applyWttr(doc) {
    var now = doc.current_condition && doc.current_condition.length ? doc.current_condition[0] : null
    if (!now) return false
    weather.current = {
      tempC: Math.round(Number(now.temp_C)),
      feelsC: Math.round(Number(now.FeelsLikeC)),
      humidity: Math.round(Number(now.humidity)),
      windKmh: Math.round(Number(now.windspeedKmph)),
      code: weather.wwoToWmo(Number(now.weatherCode)),
      isDay: true
    }
    var list = Array.isArray(doc.weather) ? doc.weather : []
    var out = []
    for (var i = 0; i < list.length && out.length < 3; i++) {
      var day = list[i]
      var hours = day.hourly || []
      var noon = hours.length > 4 ? hours[4] : (hours.length ? hours[hours.length - 1] : null)
      out.push({
        date: String(day.date || ""),
        code: weather.wwoToWmo(noon ? Number(noon.weatherCode) : 113),
        maxC: Math.round(Number(day.maxtempC)),
        minC: Math.round(Number(day.mintempC))
      })
    }
    weather.days = out
    if (!weather.place && doc.nearest_area && doc.nearest_area.length) {
      var area = doc.nearest_area[0]
      if (area.areaName && area.areaName.length) weather.place = String(area.areaName[0].value || "")
    }
    return true
  }

  // wttr.in speaks WWO codes while the rest of this file speaks WMO. Only the
  // icon and the wording depend on it, so a coarse mapping is enough.
  function wwoToWmo(code) {
    if (code === 113) return 0
    if (code === 116) return 2
    if (code === 119 || code === 122) return 3
    if (code === 143 || code === 248) return 45
    if (code === 260) return 48
    if (code === 200 || code === 386 || code === 389 || code === 392 || code === 395) return 95
    if ([179, 182, 185, 227, 230, 281, 284, 311, 314, 317, 320, 323, 326, 329, 332,
         335, 338, 350, 362, 365, 368, 371, 374, 377].indexOf(code) !== -1) return 71
    if ([176, 263, 266, 293, 296, 353].indexOf(code) !== -1) return 51
    return 61
  }

  // ---------- Presentation ----------

  function iconFor(code, night) {
    code = Number(code)
    if (code === 0) return night ? "🌙" : "☀️"
    if (code === 1 || code === 2) return night ? "🌙" : "⛅"
    if (code === 3) return "☁️"
    if (code === 45 || code === 48) return "🌫️"
    if (code >= 51 && code <= 57) return "🌦️"
    if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return "🌧️"
    if ((code >= 71 && code <= 77) || code === 85 || code === 86) return "❄️"
    if (code >= 95) return "⛈️"
    return "🌧️"
  }

  readonly property var conditions: ({
    0: "Clear", 1: "Mainly clear", 2: "Partly cloudy", 3: "Overcast",
    45: "Fog", 48: "Rime fog",
    51: "Light drizzle", 53: "Drizzle", 55: "Dense drizzle",
    56: "Freezing drizzle", 57: "Freezing drizzle",
    61: "Light rain", 63: "Rain", 65: "Heavy rain",
    66: "Freezing rain", 67: "Freezing rain",
    71: "Light snow", 73: "Snow", 75: "Heavy snow", 77: "Snow grains",
    80: "Light showers", 81: "Showers", 82: "Violent showers",
    85: "Snow showers", 86: "Heavy snow showers",
    95: "Thunderstorm", 96: "Thunderstorm with hail", 99: "Thunderstorm with hail"
  })

  function condition(code) { return weather.conditions[Number(code)] || "" }

  // The chip's label: "+6°C", keeping the sign convention the island already
  // used so the chip does not change width every time it crosses zero.
  function chipLabel() {
    if (!weather.current) return ""
    var t = weather.current.tempC
    return (t > 0 ? "+" : "") + t + "°C"
  }

  function dayName(dateText) {
    var d = new Date(String(dateText) + "T12:00:00")
    if (isNaN(d.getTime())) return ""
    return d.toDateString() === new Date().toDateString() ? "Today" : Qt.formatDateTime(d, "ddd")
  }
}
