function nameForPath(path) {
  return String(path || "").split("/").pop().replace(/\.[^/.]+$/, "")
}

function titleize(name) {
  return String(name || "").replace(/[-_]+/g, " ").replace(/\b\w/g, function(match) { return match.toUpperCase() })
}

function labelForPath(path) {
  return titleize(nameForPath(path))
}

// A row is `filePath \t thumbnailPath \t group`, the group optional. Rows
// sharing a group collapse into one carousel item; the rest of the group
// becomes variants the picker cycles through with up/down.
function loadRows(rows) {
  var images = []
  var seen = {}
  var groups = {}
  var lines = String(rows || "").split("\n")

  for (var i = 0; i < lines.length; i++) {
    var row = lines[i]
    if (!row) continue

    var columns = row.split("\t")
    var path = columns[0]
    if (!path) continue

    var fileName = path.split("/").pop()
    var group = columns[2] || ""
    var key = group + "\n" + fileName
    if (seen[key]) continue
    seen[key] = true

    var variant = {
      filePath: path,
      fileName: fileName,
      thumbnailPath: columns[1] || path
    }

    if (group && groups.hasOwnProperty(group)) {
      images[groups[group]].variants.push(variant)
      continue
    }

    if (group) groups[group] = images.length

    images.push({
      filePath: variant.filePath,
      fileName: variant.fileName,
      thumbnailPath: variant.thumbnailPath,
      group: group,
      variants: [variant]
    })
  }

  return images
}

function variantsOf(images, index) {
  if (!Array.isArray(images) || index < 0 || index >= images.length) return []
  return images[index].variants || [images[index]]
}

function variantCount(images, index) {
  return variantsOf(images, index).length
}

function variantAt(images, index, variant) {
  var variants = variantsOf(images, index)
  if (variants.length === 0) return null

  var position = variant % variants.length
  if (position < 0) position += variants.length

  return variants[position]
}

function maxVariantCount(images) {
  var values = Array.isArray(images) ? images : []
  var most = 0

  for (var i = 0; i < values.length; i++) {
    most = Math.max(most, variantCount(values, i))
  }

  return most
}

// A grouped item's own file is only the first of several; the group is what the
// user is choosing.
function nameForItem(images, index) {
  if (!Array.isArray(images) || index < 0 || index >= images.length) return ""

  var item = images[index]
  return item.group ? item.group : nameForPath(item.filePath)
}

function labelForItem(images, index) {
  return titleize(nameForItem(images, index))
}

function itemMatches(images, index, filterText) {
  if (!Array.isArray(images) || index < 0 || index >= images.length) return false
  var needle = String(filterText || "").toLowerCase()
  if (!needle) return true

  var name = nameForItem(images, index)
  return name.toLowerCase().indexOf(needle) !== -1
      || titleize(name).toLowerCase().indexOf(needle) !== -1
}

function firstMatchingIndex(images, filterText) {
  var values = Array.isArray(images) ? images : []
  for (var i = 0; i < values.length; i++) {
    if (itemMatches(values, i, filterText)) return i
  }

  return -1
}

function filteredPosition(images, index, filterText) {
  if (!filterText) return index

  var position = 0
  for (var i = 0; i < index; i++) {
    if (itemMatches(images, i, filterText)) position++
  }

  return position
}

function selectedFilteredPosition(images, selectedIndex, filterText) {
  if (!filterText) return selectedIndex
  return itemMatches(images, selectedIndex, filterText) ? filteredPosition(images, selectedIndex, filterText) : 0
}

// Which item a path sits in, and which of that item's variants.
function locateImage(images, selectedImage) {
  var values = Array.isArray(images) ? images : []
  for (var i = 0; i < values.length; i++) {
    var variants = variantsOf(values, i)
    for (var variant = 0; variant < variants.length; variant++) {
      if (variants[variant].filePath === selectedImage) return { index: i, variant: variant }
    }
  }

  return { index: 0, variant: 0 }
}

function indexForSelectedImage(images, selectedImage) {
  return locateImage(images, selectedImage).index
}

function nextSelectedIndexForFilter(images, selectedIndex, filterText) {
  if (itemMatches(images, selectedIndex, filterText)) return selectedIndex
  return firstMatchingIndex(images, filterText)
}

if (typeof module !== "undefined") {
  module.exports = {
    nameForPath: nameForPath,
    labelForPath: labelForPath,
    loadRows: loadRows,
    variantsOf: variantsOf,
    variantCount: variantCount,
    variantAt: variantAt,
    maxVariantCount: maxVariantCount,
    nameForItem: nameForItem,
    labelForItem: labelForItem,
    itemMatches: itemMatches,
    firstMatchingIndex: firstMatchingIndex,
    filteredPosition: filteredPosition,
    selectedFilteredPosition: selectedFilteredPosition,
    locateImage: locateImage,
    indexForSelectedImage: indexForSelectedImage,
    nextSelectedIndexForFilter: nextSelectedIndexForFilter
  }
}
