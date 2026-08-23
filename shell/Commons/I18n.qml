pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "I18nModel.js" as Model

QtObject {
  id: root

  property var availableCatalogs: []
  readonly property string catalog: Model.selectCatalog({
    LANGUAGE: Quickshell.env("LANGUAGE"),
    LC_ALL: Quickshell.env("LC_ALL"),
    LC_MESSAGES: Quickshell.env("LC_MESSAGES"),
    LANG: Quickshell.env("LANG")
  }, availableCatalogs)
  readonly property string translationsPath: catalog
    ? Quickshell.env("OMARCHY_PATH") + "/shell/translations/" + catalog + ".json"
    : ""
  property var translations: ({})

  function tr(source, args) {
    return Model.translate(source, translations, args)
  }

  function ntr(count, singular, plural, args) {
    return Model.translatePlural(count, singular, plural, translations, args)
  }

  function loadCatalogs(raw) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      availableCatalogs = Array.isArray(parsed) ? parsed.filter(function(value) { return typeof value === "string" }) : []
    } catch (error) {
      console.warn("translation catalog manifest parse failed:", error)
      availableCatalogs = []
    }
  }

  function load(raw) {
    var text = String(raw || "").trim()
    if (!text) {
      translations = ({})
      return
    }
    try {
      var parsed = JSON.parse(text)
      translations = parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : ({})
    } catch (error) {
      console.warn("translation catalog parse failed:", translationsPath, error)
      translations = ({})
    }
  }

  property FileView catalogFile: FileView {
    path: root.translationsPath
    watchChanges: true
    printErrors: false
    onLoaded: root.load(text())
    onLoadFailed: function(error) { root.load("") }
    onFileChanged: reload()
  }


  property FileView catalogsFile: FileView {
    path: Quickshell.env("OMARCHY_PATH") + "/shell/translations/catalogs.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadCatalogs(text())
    onLoadFailed: function(error) { root.loadCatalogs("") }
    onFileChanged: reload()
  }
}
