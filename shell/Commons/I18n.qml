pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property string locale: {
    var lang = Quickshell.env("LANG") || Quickshell.env("LC_ALL") || "en_US.UTF-8"
    return lang.split(".")[0].split("_")[0].toLowerCase()
  }

  property var translations: ({})
  property bool loaded: false

  function tr(key, args) {
    var val = translations[key]
    if (val === undefined || val === null) return key
    if (args) {
      for (var i = 0; i < args.length; i++) {
        val = val.replace("{" + i + "}", args[i])
      }
    }
    return val
  }

  function trPlural(key, count, args) {
    var pluralKey = count === 1 ? key : key + "_plural"
    var val = translations[pluralKey] || translations[key] || key
    if (args) {
      for (var i = 0; i < args.length; i++) {
        val = val.replace("{" + i + "}", args[i])
      }
    }
    return val.replace("{count}", count)
  }

  Component.onCompleted: {
    var path = Quickshell.env("OMARCHY_PATH") + "/shell/translations/" + locale + ".json"
    translationFile.path = path
    translationFile.reload()
  }

  FileView {
    id: translationFile
    watchChanges: false
    printErrors: false
    onLoaded: {
      var content = text()
      if (!content) {
        root.loaded = true
        return
      }
      try {
        root.translations = JSON.parse(content)
      } catch (e) {
        root.translations = {}
      }
      root.loaded = true
    }
    onLoadFailed: {
      root.translations = {}
      root.loaded = true
    }
  }
}
