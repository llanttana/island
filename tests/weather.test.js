#!/usr/bin/env node
// The weather switch, over every value a settings file can hold. The real
// WeatherLogic.js is loaded in a vm context, the way the other tests load their
// module.
const fs = require("fs"), path = require("path"), vm = require("vm")
const src = fs.readFileSync(path.join(__dirname, "..", "components", "WeatherLogic.js"), "utf8")
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

console.log("the switch")
check("on is on", M.enabled("on"), true)
check("off is off", M.enabled("off"), false)
check("a missing key is on, as it always was", M.enabled(undefined), true)
check("an absent key (null) is on", M.enabled(null), true)
check("an empty value is on", M.enabled(""), true)
check("only the exact word turns it off", M.enabled("OFF"), true)
check("and nothing else does either", M.enabled("no"), true)
check("a false in the file is on too", M.enabled(false), true)

console.log("the chip")
check("on with a label: shown", M.chipVisible("on", "12°"), true)
check("off with a label: hidden", M.chipVisible("off", "12°"), false)
check("off, and no label either", M.chipVisible("off", ""), false)
check("a missing key with a label: shown", M.chipVisible(undefined, "12°"), true)
check("on but nothing to say: hidden", M.chipVisible("on", ""), false)
check("on and an absent label: hidden", M.chipVisible("on", undefined), false)
check("a numeric label still counts", M.chipVisible("on", 12), true)

console.log(`\n${pass} passed, ${fail} failed`)
process.exit(fail === 0 ? 0 : 1)
