// Shelf items: files, images, links and text parked on the island. Pure
// helpers only. The island keeps the live list in memory and writes nothing to
// disk, so a shell restart (or reboot) empties the shelf.

function decodeFileUri(uri) {
  var value = String(uri || "").trim()
  if (value.indexOf("file://") !== 0) return ""
  var path = value.substring(7)
  if (path.indexOf("localhost/") === 0) path = path.substring(9)
  if (path.charAt(0) !== "/") return ""
  try { return decodeURIComponent(path) } catch (e) { return path }
}

function fileName(path) {
  var parts = String(path || "").split("/")
  return parts.length > 0 ? parts[parts.length - 1] : String(path || "")
}

function isImagePath(path) {
  return /\.(png|jpe?g|webp|gif|bmp|tiff?)$/i.test(String(path || ""))
}

function label(item) {
  if (!item) return ""
  if (item.kind === "file" || item.kind === "image") return String(item.name || fileName(item.path))
  var text = String(item.text || "").replace(/\s+/g, " ").trim()
  if (item.kind === "url") return String(item.name || text)
  return text.length > 64 ? text.slice(0, 64) + "\u2026" : text
}

// One candidate (from the clipboard list, or the clipboard itself) as a shelf
// item, or null when it has nothing to hold on to.
function normalize(value) {
  if (!value || typeof value !== "object") return null
  var kind = String(value.kind || value.type || "")
  if (kind === "file" || kind === "image") {
    var path = String(value.path || "")
    if (!path) return null
    return {
      kind: kind,
      path: path,
      name: String(value.name || fileName(path)),
      mime: String(value.mime || (kind === "image" ? "image/png" : "text/plain"))
    }
  }
  if (kind === "url") {
    var url = String(value.text || value.url || "").trim()
    if (!/^https?:\/\//i.test(url)) return null
    return { kind: "url", text: url, name: String(value.name || url) }
  }
  if (kind === "text") {
    var text = String(value.text || "")
    if (!text.trim()) return null
    return { kind: "text", text: text, name: String(value.name || label({ kind: "text", text: text })) }
  }
  return null
}

function itemKey(item) {
  if (!item) return ""
  if (item.kind === "file" || item.kind === "image") return item.kind + ":" + String(item.path || "")
  return item.kind + ":" + String(item.text || "")
}

// Newest first, deduped by identity: adding an item already on the shelf moves
// it back to the front instead of duplicating it.
function add(items, value) {
  var list = Array.isArray(items) ? items.slice() : []
  var item = normalize(value)
  if (!item) return list
  var key = itemKey(item)
  var next = [item]
  for (var i = 0; i < list.length; i++) {
    if (itemKey(list[i]) === key) continue
    next.push(list[i])
  }
  return next
}

function removeKey(items, key) {
  var list = Array.isArray(items) ? items : []
  var out = []
  for (var i = 0; i < list.length; i++)
    if (itemKey(list[i]) !== key) out.push(list[i])
  return out
}

// A clipboard payload as shelf items: a text/uri-list becomes one item per
// file, a bare http(s) URL becomes a link, anything else is text.
function fromText(raw) {
  var text = String(raw || "")
  if (!text.trim()) return []

  var lines = text.split(/\r?\n/)
  var paths = []
  for (var i = 0; i < lines.length; i++) {
    var path = decodeFileUri(lines[i])
    if (path) paths.push(path)
  }
  if (paths.length > 0) {
    var files = []
    for (var j = 0; j < paths.length; j++) {
      var image = isImagePath(paths[j])
      files.push({
        kind: image ? "image" : "file",
        path: paths[j],
        name: fileName(paths[j]),
        mime: image ? "image/png" : "text/plain"
      })
    }
    return files
  }

  var trimmed = text.trim()
  if (/^https?:\/\//i.test(trimmed)) return [{ kind: "url", text: trimmed, name: trimmed }]
  return [{ kind: "text", text: text, name: label({ kind: "text", text: text }) }]
}

function searchText(item) {
  if (!item) return ""
  return (String(item.name || "") + " " + String(item.path || "") + " " + String(item.text || "")).toLowerCase()
}

if (typeof module !== "undefined") {
  module.exports = {
    decodeFileUri: decodeFileUri,
    fileName: fileName,
    isImagePath: isImagePath,
    label: label,
    normalize: normalize,
    itemKey: itemKey,
    add: add,
    removeKey: removeKey,
    fromText: fromText,
    searchText: searchText
  }
}
