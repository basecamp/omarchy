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
    deviceLists: deviceLists,
    cloneMap: cloneMap,
    pendingAction: pendingAction,
    withPendingAction: withPendingAction,
    visibleSections: visibleSections,
    sectionDevices: sectionDevices
  }
}
