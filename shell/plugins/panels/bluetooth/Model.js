// BlueZ keeps two names for every device: Name, the one the device itself
// advertises, and Alias, the friendly name the user can set. Alias defaults to
// Name, and BlueZ restores that default the moment Alias is written an empty
// string. Quickshell surfaces them as deviceName (read-only) and name
// (writable), so name is the one the user chose and it wins wherever a device
// is labelled — falling back to the advertised name only when there is no
// alias at all.
function friendlyName(device) {
  if (!device) return ""
  return String(device.name || "").trim()
}

function defaultName(device) {
  if (!device) return ""
  return String(device.deviceName || "").trim()
}

function deviceLabel(device) {
  if (!device) return ""
  return friendlyName(device) || defaultName(device)
}

// True only when the alias actually differs from the advertised name, rather
// than BlueZ mirroring one into the other. The editor shows the advertised
// name as its placeholder so what clearing the field restores is visible
// before it is cleared.
function hasFriendlyName(device) {
  var friendly = friendlyName(device)
  return friendly !== "" && friendly !== defaultName(device)
}

// Every name a device answers to, friendly one first. PipeWire is not
// consistent about which of the two it copies into a node — bluez5 nodes carry
// the alias in some properties and the advertised name in others — so matching
// has to try both, or renaming a speaker would cost it its audio-sink match.
function deviceNames(device) {
  var names = []
  var friendly = friendlyName(device)
  var fallback = defaultName(device)
  if (friendly !== "") names.push(friendly)
  if (fallback !== "" && fallback !== friendly) names.push(fallback)
  return names
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

// Whether a device is real enough to list, which is a question about the
// device and not about what its owner called it. Both names are asked, because
// judging by the label alone would let an address- or UUID-shaped alias — a
// legal thing to type into the rename editor — drop the device out of every
// section, including the row needed to type something else.
function hasHumanName(device) {
  var names = deviceNames(device)
  for (var i = 0; i < names.length; i++) {
    if (!isUuidLike(names[i]) && !isAddressLike(names[i])) return true
  }
  return false
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

function bluetoothSinkMatchesDevice(node, device) {
  if (!node || !node.isSink || node.isStream || !device) return false

  var address = normalizedAddress(device.address)
  var text = nodeText(node)
  if (address !== "" && normalizedAddress(text).indexOf(address) !== -1) return true

  var names = deviceNames(device)
  for (var n = 0; n < names.length; n++) {
    if (text.indexOf(names[n].toLowerCase()) !== -1) return true
  }
  return false
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
    if (!d || !hasHumanName(d)) continue
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
    friendlyName: friendlyName,
    defaultName: defaultName,
    hasFriendlyName: hasFriendlyName,
    deviceNames: deviceNames,
    toArray: toArray,
    isUuidLike: isUuidLike,
    isAddressLike: isAddressLike,
    normalizedAddress: normalizedAddress,
    hasHumanName: hasHumanName,
    nodeProps: nodeProps,
    nodeText: nodeText,
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
