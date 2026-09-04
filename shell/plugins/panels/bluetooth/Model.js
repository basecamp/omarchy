// BlueZ's Alias (device.name) is the user-facing name: what the user set if
// they renamed the device, and a copy of the device-reported Name otherwise.
// deviceName is Name itself — the fallback for a device that never reported
// one, and for the window between clearing an alias and BlueZ echoing the
// name back, where quickshell's optimistic write leaves the alias empty.
function deviceLabel(device) {
  if (!device) return ""
  return String((device.name || device.deviceName) || "").trim()
}

function deviceRealName(device) {
  if (!device) return ""
  return String(device.deviceName || "").trim()
}

// A device carries a user-set alias when BlueZ reports an Alias that is not
// simply a copy of Name. Two cases read as "no alias" deliberately: an alias
// typed to match the device name exactly, which is indistinguishable and whose
// removal would change nothing on screen, and the empty alias quickshell holds
// locally while a clear is still in flight.
function hasAlias(device) {
  var alias = device ? String(device.name || "").trim() : ""
  return alias !== "" && alias !== deviceRealName(device)
}

function toArray(values) {
  if (!values) return []
  if (Array.isArray(values)) return values.slice()

  var length = Number(values.length || 0)
  if (!isFinite(length) || length <= 0) return []

  var list = []
  for (var i = 0; i < length; i++) list.push(values[i])
  return list
}

function isUuidLike(value) {
  var text = String(value || "").trim()
  if (text === "") return false
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(text)
    || /^[0-9a-f]{32}$/i.test(text)
    || /^0x[0-9a-f]{4,32}$/i.test(text)
    || /^0000[0-9a-f]{4}-0000-1000-8000-00805f9b34fb$/i.test(text)
}

function isAddressLike(value) {
  var text = String(value || "").trim()
  return /^([0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i.test(text)
}

function normalizedAddress(value) {
  return String(value || "").trim().toLowerCase().replace(/[^0-9a-f]/g, "")
}

function isHumanName(label) {
  return label !== "" && !isUuidLike(label) && !isAddressLike(label)
}

// Either name qualifies a device for the lists. A device with a real name is
// never hidden by a MAC-shaped alias — that would be unrecoverable from the
// panel, which is the only place the alias can be changed back — and a device
// whose reported name is junk becomes listable once it has one worth showing.
function hasHumanName(device) {
  return isHumanName(deviceLabel(device)) || isHumanName(deviceRealName(device))
}

function nodeProps(node) {
  return node && node.ready && node.properties ? node.properties : {}
}

function nodeText(node) {
  var props = nodeProps(node)
  return [
    node ? node.name : "",
    node ? node.description : "",
    node ? node.nickname : "",
    node ? node.nick : "",
    props["node.name"],
    props["node.description"],
    props["node.nick"],
    props["device.name"],
    props["device.description"],
    props["device.product.name"],
    props["device.alias"],
    props["device.string"],
    props["api.bluez5.address"],
    props["bluez5.address"],
    props["media.name"]
  ].join(" ").toLowerCase()
}

function isCandidateSink(node, device) {
  return !!node && !!node.isSink && !node.isStream && !!device
}

// An exact identifier: the device's address, as PipeWire spells it into a
// bluez_output node's name and properties.
function bluetoothSinkMatchesAddress(node, device) {
  if (!isCandidateSink(node, device)) return false
  var address = normalizedAddress(device.address)
  if (address === "") return false
  return normalizedAddress(nodeText(node)).indexOf(address) !== -1
}

// A substring guess, for a sink that carries no address at all.
function bluetoothSinkMatchesName(node, device) {
  if (!isCandidateSink(node, device)) return false
  var text = nodeText(node)

  // Prefer the name the device reports. PipeWire fills a node's properties when
  // the device connects and does not follow a later alias change, so that is
  // what is actually in there — whereas an alias is a short label the user
  // chose, and as an unconstrained substring it matches unrelated nodes ("Pro"
  // is in pro-output-3, "Car" is in alsa_card). An alias is only consulted for
  // a device that reports no name of its own, where it is the only string
  // there is. Nothing else is lost: a node that could carry the alias is a
  // bluez_output node, and those carry the address matched above.
  var name = (deviceRealName(device) || deviceLabel(device)).toLowerCase()
  return name !== "" && text.indexOf(name) !== -1
}

// Kept for callers that just want "does this sink belong to this device"; the
// panel applies the two criteria in separate passes so an exact address match
// is never beaten by a name guess on an earlier sink.
function bluetoothSinkMatchesDevice(node, device) {
  return bluetoothSinkMatchesAddress(node, device) || bluetoothSinkMatchesName(node, device)
}

function sortedByLabel(devices) {
  var list = toArray(devices)
  list.sort(function(a, b) { return deviceLabel(a).localeCompare(deviceLabel(b)) })
  return list
}

// Primitives-only projection of a BlueZ device for list-model rows. Holding
// the Device QObject in model data puts a live wrapper into every delegate's
// var property, and BlueZ churn (discovery timeouts, unpair) can destroy the
// object while a delegate is still incubating, which segfaults quickshell.
// Actions resolve the backend object via Panel.deviceFor().
function deviceRow(d) {
  if (!d) return null
  return {
    address: d.address || "",
    name: d.name || "",
    deviceName: d.deviceName || "",
    connected: !!d.connected,
    state: d.state !== undefined ? d.state : -1,
    batteryAvailable: !!d.batteryAvailable,
    battery: d.battery !== undefined ? d.battery : 0,
    pairing: !!d.pairing
  }
}

function deviceLists(devices) {
  var values = toArray(devices)
  var connected = []
  var known = []
  var discovered = []

  for (var i = 0; i < values.length; i++) {
    var d = values[i]
    if (!d) continue
    // The name filter is here to keep junk out of a scan, not to police devices
    // BlueZ has a stored record for: a remembered device stays listed whatever
    // it ends up called, or naming one something address-shaped would hide the
    // only row that could name it back. Connected-but-never-paired is still a
    // scan result, so it stays filtered.
    var remembered = d.paired || d.bonded || d.trusted
    if (!remembered && !hasHumanName(d)) continue
    if (d.connected) connected.push(d)
    else if (d.paired || d.bonded || d.trusted) known.push(d)
    else discovered.push(d)
  }

  return {
    connected: sortedByLabel(connected),
    known: sortedByLabel(known),
    discovered: sortedByLabel(discovered)
  }
}

function cloneMap(map) {
  var next = ({})
  for (var key in map || {}) next[key] = map[key]
  return next
}

function pendingAction(actions, address) {
  return address && actions && actions[address] ? actions[address] : ""
}

function withPendingAction(actions, address, action) {
  var next = cloneMap(actions)
  if (!address) return next
  if (action) next[address] = action
  else delete next[address]
  return next
}

function visibleSections(lists, discovering) {
  var sections = []
  if (lists && lists.connected && lists.connected.length > 0) sections.push("connected")
  if (lists && lists.known && lists.known.length > 0) sections.push("known")
  if (discovering && lists && lists.discovered && lists.discovered.length > 0) sections.push("discovered")
  return sections
}

function sectionDevices(lists, section) {
  if (!lists) return []
  if (section === "connected") return lists.connected || []
  if (section === "known") return lists.known || []
  if (section === "discovered") return lists.discovered || []
  return []
}

if (typeof module !== "undefined") {
  module.exports = {
    deviceLabel: deviceLabel,
    deviceRealName: deviceRealName,
    hasAlias: hasAlias,
    toArray: toArray,
    isUuidLike: isUuidLike,
    isAddressLike: isAddressLike,
    normalizedAddress: normalizedAddress,
    isHumanName: isHumanName,
    hasHumanName: hasHumanName,
    nodeProps: nodeProps,
    nodeText: nodeText,
    bluetoothSinkMatchesAddress: bluetoothSinkMatchesAddress,
    bluetoothSinkMatchesName: bluetoothSinkMatchesName,
    bluetoothSinkMatchesDevice: bluetoothSinkMatchesDevice,
    sortedByLabel: sortedByLabel,
    deviceRow: deviceRow,
    deviceLists: deviceLists,
    cloneMap: cloneMap,
    pendingAction: pendingAction,
    withPendingAction: withPendingAction,
    visibleSections: visibleSections,
    sectionDevices: sectionDevices
  }
}
