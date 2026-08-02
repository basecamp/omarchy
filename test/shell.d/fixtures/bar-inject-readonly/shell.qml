import QtQuick
import Quickshell

ShellRoot {
  id: root

  function fail(message) {
    console.log("RESULT fail " + message)
    Qt.quit()
  }

  // Reproduces ModuleSlot.injectProps inside Bar.qml: a custom widget such as
  // CustomCommandModule declares `readonly property string moduleName` and
  // `readonly property var settings`. QML's `in` still reports those keys, so
  // an unguarded assignment throws an engine TypeError on non-writable props;
  // the try/catch is what makes injection safe. Verify that behavior directly
  // against the real engine rather than a source string.
  function checkWritable(target, key, value, changed) {
    if (!(key in target)) return
    var before = target[key]
    try {
      target[key] = value
    } catch (error) {
      if (target[key] !== before) fail(key + " changed despite a throw: " + error)
      return
    }
    if (target[key] !== value) fail(key + " assignment silently ignored")
  }

  function runChecks() {
    var target = Qt.createQmlObject('import QtQuick; QtObject { readonly property bool bar: false; readonly property string moduleName: "readonly"; readonly property var settings: ({ fixed: 1 }); property string patchable: "board" }', root, "widget")
    if (!target) {
      fail("test widget failed to instantiate")
      return
    }

    // Read-only injection mirrors injectProps: no exception may escape.
    checkWritable(target, "bar", "injected-root")
    checkWritable(target, "moduleName", "injected-name")
    checkWritable(target, "settings", ({ changed: true }))

    if (target.moduleName !== "readonly") fail("read-only moduleName was overwritten")
    if (target.bar !== false) fail("read-only bar was overwritten")
    if (target.settings.fixed !== true) fail("read-only settings map was replaced")

    // A writable property still receives injected values.
    checkWritable(target, "patchable", "injected-patch")

    console.log("RESULT pass")
    Qt.quit()
  }

  Component.onCompleted: Qt.callLater(runChecks)
}