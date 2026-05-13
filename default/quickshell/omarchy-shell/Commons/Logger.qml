pragma Singleton
import QtQuick

// Noctalia compat shim. Plugins call Logger.d/i/w/e routinely.
QtObject {
  function format(args) {
    var out = []
    for (var i = 0; i < args.length; i++) {
      var a = args[i]
      out.push(a === undefined ? "undefined" : (a === null ? "null" : String(a)))
    }
    return out.join(" ")
  }

  function d() { console.debug(format(arguments)) }
  function i() { console.info(format(arguments)) }
  function w() { console.warn(format(arguments)) }
  function e() { console.error(format(arguments)) }
}
