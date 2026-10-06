#!/usr/bin/env node
// The live-activity model: what owns the pill, what rides beside it, and what is
// left over. The test loads the real file (components/ActivityModel.js) in a vm
// context, the same way tests/ephemeral.test.js runs the companion's function,
// so this cannot drift from what the island actually runs.
const fs = require("fs")
const path = require("path")
const vm = require("vm")

const src = fs.readFileSync(path.join(__dirname, "..", "components", "ActivityModel.js"), "utf8")
const ctx = {}
vm.createContext(ctx)
vm.runInContext(src, ctx)
const M = ctx

let pass = 0, fail = 0
function check(name, actual, expected) {
  const a = JSON.stringify(actual), e = JSON.stringify(expected)
  if (a === e) { pass++; console.log(`  ok    ${name}`) }
  else { fail++; console.log(`  FAIL  ${name}\n        expected ${e}\n        got      ${a}`) }
}
function act(id, source, over) {
  const base = { id, source, text: id, priority: M.PRIORITY[source], createdAt: 1000, ttl: 0 }
  return Object.assign(base, over || {})
}
const T = 5000

console.log("order")
check("priority decides", M.order([act("m", "media"), act("t", "timer")], T).map(a => a.id), ["t", "m"])
check("equal priority: the earlier one first",
  M.order([act("b", "download", { createdAt: 200 }), act("a", "update", { createdAt: 100 })], T).map(a => a.id), ["a", "b"])
check("same priority and time: id breaks the tie",
  M.order([act("z", "download"), act("a", "download")], T).map(a => a.id), ["a", "z"])
check("expired entries are left out",
  M.order([act("old", "timer", { createdAt: 0, ttl: 1000 }), act("new", "media")], T).map(a => a.id), ["new"])
check("ttl 0 never expires", M.order([act("forever", "timer", { createdAt: 0 })], 10 ** 9).length, 1)
const input = [act("m", "media"), act("t", "timer")]
M.order(input, T)
check("order does not mutate the list", input.map(a => a.id), ["m", "t"])

console.log("visible and rest")
const many = [act("a", "timer"), act("b", "download"), act("c", "media"), act("d", "system")]
check("visible(1) is the owner", M.visible(many, 1, T).map(a => a.id), ["a"])
check("visible(2) is the owner and the satellite", M.visible(many, 2, T).map(a => a.id), ["a", "b"])
check("rest counts the leftovers", M.rest(many, 2, T), 2)
check("rest never goes below zero", M.rest([act("a", "timer")], 2, T), 0)

console.log("one slot for downloads and updates")
check("the older one of the two wins the slot",
  M.slotOf([act("u", "update", { createdAt: 200 }), act("d", "download", { createdAt: 100 })], T).id, "d")
check("no download or update: no slot owner", M.slotOf([act("t", "timer")], T), null)

console.log("upsert and remove")
check("upsert replaces by id", M.upsert([act("a", "timer")], act("a", "timer", { text: "new" }), T).length, 1)
check("upsert appends", M.upsert([act("a", "timer")], act("b", "media"), T).length, 2)
const over = []
for (let i = 0; i < 9; i++) over.push(act("id" + i, "media", { createdAt: 1000 + i }))
const capped = M.upsert(over, act("fresh", "timer", { createdAt: 9000 }), T)
check("the cap holds", capped.length, M.LIMITS.activities)
check("the timer survives the cap", capped.some(a => a.id === "fresh"), true)
check("remove drops one", M.remove([act("a", "timer"), act("b", "media")], "a").map(a => a.id), ["b"])

console.log("sanitize")
check("plain input is accepted", M.sanitize({ id: "x", source: "timer", text: "ok" }, T).ok, true)
check("a missing id is refused", M.sanitize({ source: "timer", text: "ok" }, T).ok, false)
check("an unknown source is refused", M.sanitize({ id: "x", source: "kernel", text: "ok" }, T).ok, false)
check("__proto__ in the payload is refused",
  M.sanitize(JSON.parse('{"id":"x","source":"timer","text":"ok","__proto__":{"polluted":1}}'), T).ok, false)
check("control characters are stripped",
  M.sanitize({ id: "x", source: "timer", text: "a\u0000b\tc\nd" }, T).value.text, "a b c d")
check("bidi overrides are stripped",
  M.sanitize({ id: "x", source: "timer", text: "safe\u202egnip" }, T).value.text, "safegnip")
check("text is cut to the limit by grapheme",
  Array.from(M.sanitize({ id: "x", source: "timer", text: "🙂".repeat(60) }, T).value.text).length, M.LIMITS.text)
check("progress above one is refused", M.sanitize({ id: "x", source: "timer", text: "ok", progress: 2 }, T).ok, false)
check("a negative ttl is refused", M.sanitize({ id: "x", source: "timer", text: "ok", ttl: -1 }, T).ok, false)
check("a non-numeric priority is refused", M.sanitize({ id: "x", source: "timer", text: "ok", priority: "high" }, T).ok, false)
check("an external activity cannot outrank the timer",
  M.sanitize({ id: "e", source: "ext", text: "ok", priority: 100 }, T).value.priority, 79)
check("an id with a slash is refused", M.sanitize({ id: "a/b", source: "timer", text: "ok" }, T).ok, false)

console.log("external activities stay below the timer")
check("the sanitize cap is 79", M.LIMITS.externalPriority, 79)
check("sanitize clamps an external to 79",
  M.sanitize({ id: "e", source: "ext", text: "ok", priority: 100 }, T).value.priority, 79)
check("an external cannot tie with the timer",
  M.order([act("e", "ext", { priority: 80 }), act("t", "timer", { priority: 80 })], T).map(a => a.id), ["t", "e"])
check("a hand-built external above the timer is still ranked below it",
  M.order([act("e", "ext", { priority: 100 }), act("t", "timer", { priority: 80 })], T).map(a => a.id), ["t", "e"])
check("an external still beats media",
  M.order([act("e", "ext", { priority: 79 }), act("m", "media", { priority: 40 })], T).map(a => a.id), ["e", "m"])

console.log("rate limit")
const times = [0, 100, 200, 300]
check("a burst inside one second is refused", M.allowsUpdate(times, 400), false)
check("an old burst is forgotten", M.allowsUpdate(times, 1500), true)

console.log("the engine's own built-ins")
// Measured in the real QML engine -- Qt 6.11.2, the V4 the island runs under:
//
//   * Array.from("😀" x60) has 120 elements there, not 60, so sanitize cut a
//     title to 48 UTF-16 units (24 emoji instead of 48) and, when the cut landed
//     mid-pair, left a lone high surrogate at the end: a broken character on the
//     pill. Measured with a one-off spike, not by this test.
//   * Math.round(2^53 - 1) there is 2^53 -- the value is one off, and
//     Number.MAX_SAFE_INTEGER itself is right. That only matters because
//     integer() was rounding a timestamp that is already whole.
//
// Node has the correct values for both, which is exactly why a plain run cannot
// see either difference: the engine's versions are put in their place below, and
// the model has to answer the same in that world, because that is the world it
// ships into.
const EMOJI = "\ud83d\ude00"
let sixty = ""
for (let i = 0; i < 60; i++) sixty += EMOJI

function engineLike() {
  const context = {}
  vm.createContext(context)
  // One element per UTF-16 unit, the way the engine's Array.from walks a string.
  vm.runInContext("Array.from = function (value) { var out = []; for (var i = 0; i < value.length; i++) out.push(value.charAt(i)); return out }", context)
  // And a Math.round that refuses to run at all: a whole number must not need it.
  vm.runInContext("Math.round = function () { throw new Error('the engine would round here') }", context)
  vm.runInContext(src, context)
  return context
}
const E = engineLike()

function codePoints(value) { return Array.from(value).length }   // node's Array.from, the correct one
function loneSurrogate(value) {
  for (let i = 0; i < value.length; i++) {
    const unit = value.charCodeAt(i)
    if (unit < 0xd800 || unit > 0xdfff) continue
    const next = i + 1 < value.length ? value.charCodeAt(i + 1) : 0
    if (unit <= 0xdbff && next >= 0xdc00 && next <= 0xdfff) { i++; continue }
    return true
  }
  return false
}
function sanitizeThere(input) {
  try { return E.sanitize(input, T) } catch (error) { return { ok: false, error: String(error) } }
}
const WHOLE = { id: "x", source: "timer", text: "ok", priority: 80, ttl: 1000 }

check("the substituted Array.from walks units, as the engine's does",
  vm.runInContext("Array.from(String.fromCharCode(0xd83d, 0xde00)).length", E), 2)
check("a long emoji text is cut to the limit in code points there too",
  codePoints(E.sanitize({ id: "x", source: "timer", text: sixty }, T).value.text), M.LIMITS.text)
check("text short in code points is not cut there, however many units it is",
  codePoints(E.sanitize({ id: "x", source: "timer", text: EMOJI + EMOJI }, T).value.text), 2)
check("a cut never ends on half a pair there",
  loneSurrogate(E.sanitize({ id: "x", source: "timer", text: "a" + sixty }, T).value.text), false)
check("a whole timestamp is accepted there without rounding",
  sanitizeThere({ id: "x", source: "timer", text: "ok", priority: 80, ttl: 1000, createdAt: 9007199254740991 }).ok, true)
check("and comes back unchanged", sanitizeThere({ id: "x", source: "timer", text: "ok", priority: 80, ttl: 1000, createdAt: 9007199254740991 }).value.createdAt, 9007199254740991)
check("2^53 is not a timestamp there either", sanitizeThere({ id: "x", source: "timer", text: "ok", createdAt: 9007199254740992 }).ok, false)
check("a whole priority and ttl need no rounding either", sanitizeThere(WHOLE).ok, true)

check("the bound is the largest safe integer", M.LIMITS.maxTimestamp, 9007199254740991)
check("a whole timestamp comes back unchanged here too",
  M.sanitize({ id: "x", source: "timer", text: "ok", priority: 80, ttl: 1000, createdAt: 9007199254740991 }, T).value.createdAt, 9007199254740991)
check("2^53 is not a timestamp here", M.sanitize({ id: "x", source: "timer", text: "ok", createdAt: 9007199254740992 }, T).ok, false)
check("the largest safe integer still is",
  M.sanitize({ id: "x", source: "timer", text: "ok", createdAt: M.LIMITS.maxTimestamp }, T).ok, true)
check("a 60-emoji title still lands on the limit here",
  codePoints(M.sanitize({ id: "x", source: "timer", text: sixty }, T).value.text), M.LIMITS.text)

console.log(`\n${pass} passed, ${fail} failed`)
process.exit(fail === 0 ? 0 : 1)
