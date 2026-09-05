import QtQuick
import "services/AuthServiceStore.js" as AuthServiceStore

QtObject {
  function has(id) {
    return AuthServiceStore.has(id)
  }
}
