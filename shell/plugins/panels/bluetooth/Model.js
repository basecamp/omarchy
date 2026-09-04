function deviceLabel(device) {
  if (!device) return ""
  return String(device.deviceName || device.name || "").trim()
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

function hasHumanName(device) {
  var label = deviceLabel(device)
  return label !== "" && !isUuidLike(label) && !isAddressLike(label)
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

  var label = deviceLabel(device).toLowerCase()
  return label !== "" && text.indexOf(label) !== -1
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

// Roles of one row in the device list model, in one place: the projection
// below writes them, the snapshot reads them back off the ListModel, and the
// delegate declares them as required properties.
var SCROLL_ROLES = [
  "key", "section", "sectionTitle", "indexInSection",
  "address", "name", "deviceName",
  "connected", "devState", "batteryAvailable", "battery", "pairing"
]

// A role that is not a finite number is worse than a wrong one: NaN compares
// unequal to itself, so a row carrying one would be rewritten on every rebuild
// for as long as the panel lives, and nothing would say why.
function finiteNumber(value, fallback) {
  if (value === undefined || value === null || value === "") return fallback
  var number = Number(value)
  return isFinite(number) ? number : fallback
}

// Rows are identified by section and address, so the same device showing up
// in a different section is a different row rather than an in-place edit.
function scrollRowKey(row) {
  if (!row) return ""
  return (row.section || "") + "/" + (row.dev && row.dev.address ? row.dev.address : "")
}

// A row opens a section when it is the first of its kind in the flat list.
function scrollSectionTitle(rows, index) {
  if (!rows || index < 0 || index >= rows.length) return ""
  if (index > 0 && rows[index - 1].section === rows[index].section) return ""
  return rows[index].section === "known" ? "PAIRED" : "AVAILABLE"
}

// Flat, primitives-only projection of a row for the list model. ListModel
// roles hold no nested objects, and `state` is already taken on the
// delegate's Item, so the device's connection state travels as devState.
function scrollEntry(rows, index) {
  var row = rows[index] || {}
  var device = row.dev || {}
  return {
    key: scrollRowKey(row),
    section: row.section || "",
    sectionTitle: scrollSectionTitle(rows, index),
    indexInSection: row.indexInSection !== undefined ? row.indexInSection : 0,
    address: device.address || "",
    name: device.name || "",
    deviceName: device.deviceName || "",
    connected: !!device.connected,
    devState: finiteNumber(device.state, -1),
    batteryAvailable: !!device.batteryAvailable,
    battery: finiteNumber(device.battery, 0),
    pairing: !!device.pairing
  }
}

function scrollEntries(rows) {
  var entries = []
  for (var i = 0; i < (rows || []).length; i++) entries.push(scrollEntry(rows, i))
  return entries
}

// Plain-object copy of a row read back off the ListModel, so the diff compares
// values rather than model handles and cannot be surprised by what a handle
// tracks once the ops start landing.
function scrollEntrySnapshot(item) {
  var copy = ({})
  for (var i = 0; i < SCROLL_ROLES.length; i++) copy[SCROLL_ROLES[i]] = item ? item[SCROLL_ROLES[i]] : undefined
  return copy
}

function sameScrollEntry(a, b) {
  if (!a || !b) return false
  for (var i = 0; i < SCROLL_ROLES.length; i++)
    if (a[SCROLL_ROLES[i]] !== b[SCROLL_ROLES[i]]) return false
  return true
}

// Edit script turning the entries a ListModel already holds into the ones a
// rebuild wants, applied in order. Handing a ListView a whole new model is a
// reset that drops the viewport back to the top, and discovery rebuilds the
// rows every time a device appears or times out; patching only what actually
// moved keeps the delegates, and with them the scroll position.
function scrollModelOps(current, entries) {
  var rows = (current || []).slice()
  var wanted = entries || []
  var ops = []

  for (var i = 0; i < wanted.length; i++) {
    var entry = wanted[i]
    var at = -1
    for (var j = i; j < rows.length; j++) {
      if (rows[j] && rows[j].key === entry.key) { at = j; break }
    }

    if (at === -1) {
      ops.push({ op: "insert", index: i, entry: entry })
      rows.splice(i, 0, entry)
      continue
    }

    if (at !== i) {
      ops.push({ op: "move", from: at, to: i })
      rows.splice(i, 0, rows.splice(at, 1)[0])
    }

    if (!sameScrollEntry(rows[i], entry)) {
      ops.push({ op: "set", index: i, entry: entry })
      rows[i] = entry
    }
  }

  if (rows.length > wanted.length)
    ops.push({ op: "remove", index: wanted.length, count: rows.length - wanted.length })

  return ops
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
    finiteNumber: finiteNumber,
    scrollRowKey: scrollRowKey,
    scrollSectionTitle: scrollSectionTitle,
    scrollEntries: scrollEntries,
    scrollEntrySnapshot: scrollEntrySnapshot,
    sameScrollEntry: sameScrollEntry,
    scrollModelOps: scrollModelOps,
    cloneMap: cloneMap,
    pendingAction: pendingAction,
    withPendingAction: withPendingAction,
    visibleSections: visibleSections,
    sectionDevices: sectionDevices
  }
}
