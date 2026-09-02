import QtQuick
import "services/AuthServiceStore.js" as AuthServiceStore

QtObject {
  function retain(id, service) {
    AuthServiceStore.put(id, service)
  }

  function has(id) {
    return AuthServiceStore.has(id)
  }

  function updateManifest(id, manifest) {
    AuthServiceStore.updateManifest(id, manifest)
  }
}
