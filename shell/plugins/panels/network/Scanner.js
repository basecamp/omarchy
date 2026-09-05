.pragma library

// Reference counting for WifiDevice.scannerEnabled.
//
// scannerEnabled is a plain shared bool on a long-lived WifiDevice, but the
// network bar widget is instantiated once per monitor, and again transiently
// while a plugin reload overlaps the outgoing instance, so several panel
// instances write to it. Per-instance bookkeeping cannot express "another
// panel still wants this on" or "nobody wants this on any more": a release
// from one instance stops scanning under an open panel on another monitor,
// and a claim that is never released leaves the radio scanning every 10s
// with no panel open at all (basecamp/omarchy#7896).
//
// Claims live here instead, keyed by owner. A claim is never trusted on its
// own: it counts only while its owner is still alive and still open, so an
// instance that dies without releasing cannot pin the scanner on. That makes
// the registry self-healing rather than dependent on every release path
// firing. .pragma library keeps this a single shared scope engine-wide.

var claims = []  // [{ owner, device }]

// A destroyed QObject throws on property access rather than reading back
// null, so the throw is what makes a dead owner detectable here instead of
// lingering as a permanent claim.
function ownerWants(claim) {
  try {
    return !!claim.owner && claim.owner.opened === true
  } catch (e) {
    return false
  }
}

function indexOfOwner(owner) {
  for (var i = 0; i < claims.length; i++) {
    if (claims[i].owner === owner) return i
  }
  return -1
}

// Only live, open owners count. A stale claim is ignored rather than kept.
function claimCount(device) {
  var count = 0
  for (var i = 0; i < claims.length; i++) {
    if (claims[i].device === device && ownerWants(claims[i])) count++
  }
  return count
}

// Drive the device to whatever its valid claims say. A device that is gone
// took its scanner with it, so a throw here is nothing to do.
function apply(device) {
  if (!device) return
  try {
    var wanted = claimCount(device) > 0
    if (device.scannerEnabled !== wanted) device.scannerEnabled = wanted
  } catch (e) {
  }
}

// Hold the scanner on `device` for `owner`, dropping any device this owner
// held before. A null device releases without claiming anything.
function acquire(owner, device) {
  var index = indexOfOwner(owner)
  var previous = index >= 0 ? claims[index].device : null

  if (index >= 0) claims.splice(index, 1)
  if (device) claims.push({ owner: owner, device: device })

  if (previous !== device) apply(previous)
  apply(device)
}

function release(owner) {
  acquire(owner, null)
}

// Drop claims whose owner died or closed, then drive every device that was
// mentioned -- including `device`, so a device left with no valid claims is
// forced off even when the registry never held a claim for it. This is what
// bounds a missed release, rather than trusting the caller's own claim.
function sweep(device) {
  var devices = device ? [device] : []

  for (var i = 0; i < claims.length; i++) {
    var claimed = claims[i].device
    if (claimed && devices.indexOf(claimed) === -1) devices.push(claimed)
  }

  var kept = []
  for (var j = 0; j < claims.length; j++) {
    if (ownerWants(claims[j])) kept.push(claims[j])
  }
  claims = kept

  for (var k = 0; k < devices.length; k++) apply(devices[k])
}
