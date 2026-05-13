pragma Singleton
import QtQuick

// Noctalia compat shim. Their plugins normally route translations through
// pluginApi.tr(), not this singleton, so the stub here mostly exists to
// satisfy `import qs.Commons` style usage.
QtObject {
  readonly property string langCode: "en"

  function tr(key, interp)            { return String(key === undefined ? "" : key) }
  function trp(key, count, interp)    { return String(key === undefined ? "" : key) }
  function hasTranslation(key)        { return false }

  signal translationsLoaded()
}
