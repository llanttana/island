// Live activities: which one owns the pill, which one rides beside it, and how
// many are left over. Pure functions over a plain array, no QML types and no
// state of their own, so tests/activity.test.js can run this very file under
// node instead of a copy of it.
//
// An activity is a plain object:
//   { id, source, icon, text, detail, progress, priority, createdAt, ttl, click, owner }
// Only `id`, `source` and `text` are required; everything else falls back to the
// defaults below.

var SOURCES = ["timer", "download", "update", "media", "system", "ext"]

// What the pill shows when nobody said otherwise. `ext` is deliberately never
// above the timer: a process of the same user must not be able to hide it.
var PRIORITY = { timer: 80, download: 60, update: 60, media: 40, system: 20, ext: 55 }

var LIMITS = {
  activities: 8,
  text: 48,
  detail: 24,
  id: 64,
  defaultTtl: 10000,
  maxTtl: 86400000,
  externalPriority: 80,
  updatesPerSecond: 4
}

var DEFAULT_CLICK = null

function isPlainObject(value) {
  return !!value && typeof value === "object" && !Array.isArray(value)
}

// Keys that would let a caller reach into the prototype chain. Rejecting the
// whole entry is clearer than silently dropping the key: the caller gets told.
var FORBIDDEN_KEYS = ["__proto__", "constructor", "prototype"]

// Control characters, line separators and the bidi overrides that can reorder
// what the pill appears to say. Everything here is removed, not escaped.
var CONTROL = /[\u0000-\u001f\u007f-\u009f]/g
var MARKS = /[\u200b-\u200f\u2028-\u202e\u2066-\u2069]/g

function cleanString(value, max) {
  if (typeof value !== "string") return null
  // A control character is a separator, a bidi mark is noise: keeping the first
  // as a space is what makes "a\u0000b" read as "a b" instead of "ab".
  var out = value.replace(CONTROL, " ").replace(MARKS, "").replace(/\s+/g, " ").trim()
  if (!out) return null
  var chars = Array.from(out)
  if (chars.length > max) out = chars.slice(0, max).join("")
  return out
}

function finiteNumber(value, fallback, min, max) {
  if (value === undefined || value === null || value === "") return fallback
  var n = Number(value)
  if (!isFinite(n)) return null
  if (n < min || n > max) return null
  return n
}

function integer(value, fallback, min, max) {
  var n = finiteNumber(value, fallback, min, max)
  if (n === null) return null
  return Math.round(n)
}

// The one place that decides whether an incoming activity may be stored.
// Returns { ok: true, value } or { ok: false, error } and never throws.
function sanitize(input, now) {
  if (!isPlainObject(input)) return { ok: false, error: "not an object" }
  var keys = Object.keys(input)
  for (var i = 0; i < keys.length; i++) {
    if (FORBIDDEN_KEYS.indexOf(keys[i]) >= 0) return { ok: false, error: "forbidden key: " + keys[i] }
  }
  var id = cleanString(input.id, LIMITS.id)
  if (!id) return { ok: false, error: "id is required" }
  if (!/^[A-Za-z0-9:._-]+$/.test(id)) return { ok: false, error: "id has characters outside [A-Za-z0-9:._-]" }
  var source = cleanString(input.source, 16)
  if (!source) source = "ext"
  if (SOURCES.indexOf(source) < 0) return { ok: false, error: "unknown source: " + source }
  var text = cleanString(input.text, LIMITS.text)
  if (!text) return { ok: false, error: "text is required" }
  var detail = input.detail === undefined || input.detail === null ? null : cleanString(input.detail, LIMITS.detail)
  var icon = input.icon === undefined || input.icon === null ? null : cleanString(input.icon, 64)
  var progress = input.progress === undefined || input.progress === null
    ? null : finiteNumber(input.progress, null, 0, 1)
  if (progress === null && input.progress !== undefined && input.progress !== null) {
    return { ok: false, error: "progress must be a number between 0 and 1" }
  }
  var priority = integer(input.priority, PRIORITY[source] !== undefined ? PRIORITY[source] : 55, 0, 100)
  if (priority === null) return { ok: false, error: "priority must be an integer between 0 and 100" }
  if (source === "ext" && priority > LIMITS.externalPriority) priority = LIMITS.externalPriority
  var ttl = integer(input.ttl, LIMITS.defaultTtl, 0, LIMITS.maxTtl)
  if (ttl === null) return { ok: false, error: "ttl must be an integer between 0 and " + LIMITS.maxTtl }
  var createdAt = integer(input.createdAt, now === undefined ? Date.now() : now, 0, Number.MAX_SAFE_INTEGER)
  if (createdAt === null) return { ok: false, error: "createdAt must be a number" }
  var click = null
  if (isPlainObject(input.click)) {
    if (typeof input.click.view === "string") click = { view: cleanString(input.click.view, 32) }
    else if (typeof input.click.command === "string") click = { command: cleanString(input.click.command, 64) }
  }
  return { ok: true, value: {
    id: id, source: source, icon: icon, text: text, detail: detail, progress: progress,
    priority: priority, createdAt: createdAt, ttl: ttl, click: click || DEFAULT_CLICK,
    owner: source === "ext" ? "ext" : "island"
  } }
}

function alive(entry, now) {
  if (!entry || !entry.ttl) return !!entry
  return (now - entry.createdAt) < entry.ttl
}

// Puts a list in show order: priority first, then the one that appeared first,
// then the id so equal entries still have a stable order. Never mutates the
// input and never returns the same array.
function order(list, now) {
  var at = now === undefined ? Date.now() : now
  var out = []
  var items = Array.isArray(list) ? list : []
  for (var i = 0; i < items.length; i++) {
    if (isPlainObject(items[i]) && items[i].id && alive(items[i], at)) out.push(items[i])
  }
  out.sort(function (a, b) {
    if (b.priority !== a.priority) return b.priority - a.priority
    if (a.createdAt !== b.createdAt) return a.createdAt - b.createdAt
    return a.id < b.id ? -1 : a.id > b.id ? 1 : 0
  })
  return out
}

// Downloads and updates share one slot: the winner is the older one of the two
// when their priority is equal, which is what `order` already returns first.
function slotOf(list, now) {
  var items = order(list, now)
  for (var i = 0; i < items.length; i++) {
    if (items[i].source === "download" || items[i].source === "update") return items[i]
  }
  return null
}

// What the pill draws: the first `n` in show order. `rest` is what the counter
// on the satellite stands for.
function visible(list, n, now) {
  var count = integer(n, 1, 0, LIMITS.activities)
  if (count === null) count = 1
  return order(list, now).slice(0, count)
}

function rest(list, n, now) {
  var count = integer(n, 1, 0, LIMITS.activities)
  if (count === null) count = 1
  return Math.max(0, order(list, now).length - count)
}

// Add or replace by id. Over the cap the worst entry goes: lowest priority,
// then the newest, so a burst of fresh noise cannot push out a timer.
function upsert(list, entry, now) {
  var items = Array.isArray(list) ? list.slice() : []
  for (var i = 0; i < items.length; i++) {
    if (items[i] && items[i].id === entry.id) { items[i] = entry; return items }
  }
  items.push(entry)
  while (items.length > LIMITS.activities) {
    var sorted = order(items, now)
    var drop = sorted[sorted.length - 1]
    items = items.filter(function (item) { return item !== drop })
  }
  return items
}

function remove(list, id) {
  var items = Array.isArray(list) ? list : []
  return items.filter(function (item) { return !item || item.id !== id })
}

// How much of a burst to accept: returns true at most `rate` times per second
// for one id. The caller keeps the timestamps; this only decides.
function allowsUpdate(times, now, rate) {
  var limit = rate === undefined ? LIMITS.updatesPerSecond : rate
  var at = now === undefined ? Date.now() : now
  var recent = (Array.isArray(times) ? times : []).filter(function (t) { return at - t < 1000 })
  return recent.length < limit
}
