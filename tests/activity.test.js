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
  M.sanitize({ id: "e", source: "ext", text: "ok", priority: 100 }, T).value.priority, M.LIMITS.externalPriority)
check("an id with a slash is refused", M.sanitize({ id: "a/b", source: "timer", text: "ok" }, T).ok, false)

console.log("rate limit")
const times = [0, 100, 200, 300]
check("a burst inside one second is refused", M.allowsUpdate(times, 400), false)
check("an old burst is forgotten", M.allowsUpdate(times, 1500), true)

console.log(`\n${pass} passed, ${fail} failed`)
process.exit(fail === 0 ? 0 : 1)
