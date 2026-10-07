#!/usr/bin/env node
// Which provider the Ask row uses, over every combination of the `askAi` setting
// and of what is installed. The file is the real one, loaded in a vm context the
// same way tests/activity.test.js loads the activity model.
const fs = require("fs"), path = require("path"), vm = require("vm")
const src = fs.readFileSync(path.join(__dirname, "..", "components", "AskProviders.js"), "utf8")
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

const BOTH = { claude: true, chatgpt: true }
const ONLY_CLAUDE = { claude: true, chatgpt: false }
const ONLY_CODEX = { claude: false, chatgpt: true }
const NEITHER = { claude: false, chatgpt: false }

console.log("setting claude")
check("both installed: claude", M.choose("claude", BOTH), "claude")
check("claude only: claude", M.choose("claude", ONLY_CLAUDE), "claude")
check("codex only: falls back to codex", M.choose("claude", ONLY_CODEX), "chatgpt")
check("neither: no row", M.choose("claude", NEITHER), null)

console.log("setting chatgpt (the default)")
check("both installed: codex", M.choose("chatgpt", BOTH), "chatgpt")
check("codex only: codex", M.choose("chatgpt", ONLY_CODEX), "chatgpt")
check("claude only: falls back to claude", M.choose("chatgpt", ONLY_CLAUDE), "claude")
check("neither: no row", M.choose("chatgpt", NEITHER), null)

console.log("setting none")
check("both installed: still off", M.choose("none", BOTH), null)
check("claude only: still off", M.choose("none", ONLY_CLAUDE), null)
check("codex only: still off", M.choose("none", ONLY_CODEX), null)
check("neither: still off", M.choose("none", NEITHER), null)

console.log("unreadable settings")
check("an unknown name behaves like the default: codex", M.choose("gpt-5", BOTH), "chatgpt")
check("an unknown name falls back too", M.choose("gpt-5", ONLY_CLAUDE), "claude")
check("an empty setting behaves like the default", M.choose("", ONLY_CODEX), "chatgpt")
check("an absent setting behaves like the default", M.choose(undefined, ONLY_CODEX), "chatgpt")

console.log("missing or partial availability")
check("no availability at all: no row", M.choose("claude", undefined), null)
check("an empty map: no row", M.choose("claude", {}), null)
check("only the other one known true", M.choose("claude", { chatgpt: true }), "chatgpt")
check("a truthy non-true value is not a CLI", M.choose("claude", { claude: "yes", chatgpt: 1 }), null)
check("none wins even with no availability", M.choose("none", undefined), null)

console.log(`\n${pass} passed, ${fail} failed`)
process.exit(fail === 0 ? 0 : 1)
