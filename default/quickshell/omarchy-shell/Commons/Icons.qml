pragma Singleton
import QtQuick

// Noctalia compat shim. Their plugins resolve Tabler icon names to glyphs via
// this singleton. The original ships ~3000 mappings; for v1 we cover the
// names most commonly used by the plugins in their repo and fall back to
// "?" for unknowns so missing glyphs are visually obvious.
QtObject {
  // Tabler icon names → Nerd Font glyphs. Most entries are mdi-* substitutes
  // since Omarchy installs JetBrains Mono Nerd Font which includes Material
  // Design Icons. Glyph codepoints embedded as actual chars (Python helper
  // when the write tool strips multi-byte codepoints in some positions).
  readonly property var glyphs: ({
    "bell":            "\udb80\udc9a",        // mdi-bell
    "bell-off":        "\udb80\udc9b",        // mdi-bell_off
    "bell-ring":       "\udb80\udd6b",        // mdi-bell_ring
    "clock":           "\udb80\udc50",        // mdi-clock
    "clock-outline":   "\udb80\udc51",        // mdi-clock_outline
    "wifi":            "\udb81\udda9",        // mdi-wifi
    "wifi-off":        "\udb81\uddaa",        // mdi-wifi_off
    "ethernet":        "\udb80\udc02",        // mdi-ethernet
    "bluetooth":       "\udb80\udcaf",        // mdi-bluetooth
    "bluetooth-off":   "\udb80\udcb2",        // mdi-bluetooth_off
    "volume":          "\udb81\udd7e",        // mdi-volume_high
    "volume-up":       "\udb81\udd7e",
    "volume-down":     "\udb81\udd7f",
    "volume-off":      "\udb83\udc08",        // mdi-volume_variant_off
    "volume-mute":     "\udb83\udc08",
    "headphones":      "\udb80\udecb",        // mdi-headphones
    "microphone":      "\udb80\udf6c",        // mdi-microphone
    "microphone-off":  "\udb80\udf6d",        // mdi-microphone_off
    "play":            "\udb81\udc0a",        // mdi-play
    "pause":           "\udb80\udfe4",        // mdi-pause
    "skip-back":       "\udb81\udcae",        // mdi-skip_previous
    "skip-forward":    "\udb81\udcad",        // mdi-skip_next
    "music":           "\udb81\udd5a",        // mdi-music
    "weather":         "\udb81\udd99",        // mdi-weather_sunny
    "weather-sun":     "\udb81\udd99",
    "weather-moon":    "\udb81\udd94",        // mdi-weather_night
    "weather-cloud":   "\udb81\udd90",        // mdi-weather_cloudy
    "weather-rain":    "\udb81\udd96",        // mdi-weather_pouring
    "battery":         "\udb80\udc83",        // mdi-battery
    "battery-charging": "\udb80\udc84",
    "cpu":             "\udb83\udee0",        // mdi-cpu_64_bit
    "memory":          "\udb80\udd5b",        // mdi-memory
    "tools":           "\udb80\udd64",        // mdi-tools
    "settings":        "\udb80\udc93",        // mdi-cog
    "settings-outline":"\udb80\udcbb",
    "power":           "\udb80\udc25",        // mdi-power
    "lock":            "\udb80\udd3e",        // mdi-lock
    "unlock":          "\udb80\udd3f",
    "refresh":         "\udb81\udc50",        // mdi-refresh
    "x":               "\udb80\udd56",        // mdi-close
    "check":           "\udb80\udc12",        // mdi-check
    "chevron-down":    "\udb80\udd40",
    "chevron-up":      "\udb80\udd43",
    "chevron-left":    "\udb80\udd41",
    "chevron-right":   "\udb80\udd42",
    "plus":            "\udb80\udc15",
    "minus":           "\udb80\udc16",
    "leaf":            "\udb80\udf2a",
    "rocket":          "\udb81\udc63",
    "balance":         "\udb81\uddd1",
    "moon":            "\udb81\udd94",
    "sun":             "\udb81\udd99",
    "trash":           "\udb81\udcd7",        // mdi-delete
    "edit":            "\udb80\udd66",
    "search":          "\udb80\udd6f",
    "menu":            "\udb80\udd6c",
    "home":            "\udb80\udf0c",
    "folder":          "\udb80\udd99",
    "file":            "\udb80\udd97",
    "calendar":        "\udb80\udcf7",        // mdi-calendar
    "circle":          "\udb80\udd2f"
  })

  function get(name) {
    var key = String(name || "").toLowerCase()
    if (glyphs[key]) return glyphs[key]
    return "?"
  }

  function has(name) {
    return !!glyphs[String(name || "").toLowerCase()]
  }
}
