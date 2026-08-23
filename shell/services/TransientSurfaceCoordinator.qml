import QtQuick

// One active Desktop Mode flyout. Start, Settings, Run, and later Superbar
// popouts share this so opening one closes another. Dismiss does not own
// pointer input — that would swallow the click Windows delivers underneath.
QtObject {
  id: coordinator

  property var active: null

  property var exempt: ({})

  function setExempt(key, on) {
    var next = ({})
    var k
    for (k in coordinator.exempt) next[k] = coordinator.exempt[k]
    if (on)
      next[key] = true
    else
      next[key] = false
    coordinator.exempt = next
  }

  function pointerIsExempt() {
    var k
    for (k in coordinator.exempt) {
      if (coordinator.exempt[k]) return true
    }
    return false
  }

  function request(owner) {
    if (!owner)
      return
    if (coordinator.active && coordinator.active !== owner && typeof coordinator.active.close === "function")
      coordinator.active.close()
    coordinator.active = owner
  }

  function release(owner) {
    if (coordinator.active === owner)
      coordinator.active = null
  }

  function dismiss() {
    var owner = coordinator.active
    coordinator.active = null
    if (owner && typeof owner.close === "function")
      owner.close()
  }

  function dismissOutside() {
    if (coordinator.pointerIsExempt())
      return
    coordinator.dismiss()
  }
}
