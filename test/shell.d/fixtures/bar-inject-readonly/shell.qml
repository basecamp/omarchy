import QtQuick
import Quickshell
import "BarModel.js" as BarModel

ShellRoot {
  id: root

  function fail(message) {
    console.log("RESULT fail " + message)
    Qt.quit()
  }

  // Exercises the production ModuleSlot.injectProps() implementation from
  // Bar.qml: BarModel.applyInjectableProps(). A custom widget such as
  // CustomCommandModule declares `readonly property string moduleName` and
  // `readonly property var settings`; QML's `in` still reports those keys, so
  // an unguarded assignment throws an engine TypeError on non-writable props.
  // The production helper wraps each assignment so injection still works. This
  // fixture instantiates the same object shapes and drives the real helper on
  // the real engine rather than re-implementing the guard inline.
  function makeTarget(readonly) {
    if (readonly) {
      return Qt.createQmlObject(
        'import QtQuick; QtObject { readonly property var bar: null; readonly property string moduleName: "readonly-name"; readonly property var settings: ({ fixed: 1 }); property string patchable: "board" }',
        root, "readonlyWidget")
    }
    return Qt.createQmlObject(
      'import QtQuick; QtObject { property var bar: null; property string moduleName: "writable-name"; property var settings: ({ fixed: 0 }); property string patchable: "board" }',
      root, "writableWidget")
  }

  function runChecks() {
    // A writable target must receive every injected property verbatim.
    var writable = makeTarget(false)
    BarModel.applyInjectableProps(writable, {
      bar: root,
      moduleName: "injected-name",
      settings: ({ changed: true })
    })
    if (writable.bar !== root) fail("writable bar was not injected")
    if (writable.moduleName !== "injected-name") fail("writable moduleName was not injected")
    if (writable.settings.changed !== true) fail("writable settings were not injected")

    // A read-only target must not throw, keeps every read-only key unchanged,
    // and still lets adjacent writable keys receive injection.
    var fixed = makeTarget(true)
    BarModel.applyInjectableProps(fixed, {
      bar: root,
      moduleName: "injected-name",
      settings: ({ changed: true }),
      patch: "injected-patch"
    })
    if (fixed.bar !== false) fail("read-only bar was overwritten")
    if (fixed.moduleName !== "readonly-name") fail("read-only moduleName was overwritten")
    if (fixed.settings.fixed !== 1) fail("read-only settings map was replaced")
    if (fixed.patch !== "injected-patch") fail("writable property beside read-only keys was not injected")

    console.log("RESULT pass")
    Qt.quit()
  }

  Component.onCompleted: Qt.callLater(runChecks)
}