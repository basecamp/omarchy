.pragma library

// Shared pointer-vs-keyboard cursor policy for panel rows and buttons.
//
// Enter claims the panel cursor (one highlight). Leave releases it when
// this item still owns it, including a keyboard selection — so a pointer
// leaving a row unpaints hover and drops arrow-key selection. Moving
// from one row to another claims the new row first, so the old row's
// leave does not clear the new cursor.

function applyHover(on, owns, claim, release) {
  if (on) {
    if (typeof claim === "function") claim()
    return
  }
  if (owns && typeof release === "function") release()
}
