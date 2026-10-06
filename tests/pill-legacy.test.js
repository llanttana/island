#!/usr/bin/env node
// LEGACY reference for the pill rules, copied out of Island.qml formula by
// formula. It is the baseline the activity model has to reproduce while the
// sources move onto it: the owner of the display, what a click opens, the
// booleans (which keep their old meaning -- timerPill is "a timer is running",
// not "the timer owns the display"), and the resting pill's box.
//
// The formulas are frozen in tests/fixtures/island-legacy-pills.qml and read
// from there, not from Island.qml: stage 2 rewrites the very lines they came
// from, and the reference has to stand still while that happens.
// `node tests/pill-legacy.test.js --verify-live` re-cuts every block out of the
// live sources and reports the first difference. That comparison is not part of
// tests/checks.sh on purpose: the freeze is supposed to outlive the sources.
//
// Every state in the enumeration goes through ActivityModel.activitiesFromState()
// and the answer is read back out of the activities it returns. The adapter is
// what stage 2 connects, so the adapter is what has to reproduce the reference.
// Delete this file and legacyClickTarget() in stage 3.
const fs = require("fs"), path = require("path"), vm = require("vm"), crypto = require("crypto")
const root = path.join(__dirname, "..")
const FIXTURE = path.join(__dirname, "fixtures", "island-legacy-pills.qml")
const ctx = {}; vm.createContext(ctx)
vm.runInContext(fs.readFileSync(path.join(root, "components", "ActivityModel.js"), "utf8"), ctx)
const M = ctx

// ---------------------------------------------------- the frozen extract
// A block is "== <file>:<line>" followed by the source lines as comments. Only
// the marker and the "// " prefix belong to the fixture; the text behind them
// is the source verbatim, indentation included.
function parseFixture(raw) {
  const blocks = new Map()
  let cur = null
  for (const line of raw.split("\n")) {
    const marker = /^\s*\/\/\s*==\s*(\S+):(\d+)\s*$/.exec(line)
    if (marker) {
      cur = { file: marker[1], line: Number(marker[2]), lines: [] }
      blocks.set(cur.file + ":" + cur.line, cur)
      continue
    }
    if (!cur) continue
    const body = /^\s*\/\/ ?(.*)$/.exec(line)
    if (body) { cur.lines.push(body[1]); continue }
    if (line.trim() === "") continue
    cur = null   // left the comment body, e.g. the closing brace of the root object
  }
  for (const b of blocks.values()) {
    while (b.lines.length && b.lines[b.lines.length - 1].trim() === "") b.lines.pop()
    b.expr = joinContinuations(b.lines)
    b.text = b.lines.join("\n")
  }
  return blocks
}

// The QML keeps a formula readable by continuing it on the next line when that
// line starts with an operator; joining on the same rule is what turns a block
// back into the one expression the source evaluates.
function joinContinuations(lines) {
  let out = lines.length ? lines[0] : ""
  for (let i = 1; i < lines.length; i++) {
    if (/^\s*(&&|\|\||\?|:)/.test(lines[i])) out += " " + lines[i].trim()
    else break
  }
  return out.replace(/\s+/g, " ").trim()
}

const blocks = parseFixture(fs.readFileSync(FIXTURE, "utf8"))

// ------------------------------------------------- (1) the freeze vs the source
// The one thing the fixture cannot prove about itself is that it was cut out of
// the sources honestly. This re-cuts every block from the live file and diffs
// it line by line, so drift is named, not guessed at.
let liveFail = 0
if (process.argv.includes("--verify-live")) {
  console.log("(1) the freeze against the live sources")
  for (const b of blocks.values()) {
    const live = fs.readFileSync(path.join(root, b.file), "utf8").split("\n")
    const slice = live.slice(b.line - 1, b.line - 1 + b.lines.length)
    const same = slice.join("\n") === b.text
    if (!same) liveFail++
    console.log(`  ${same ? "ok  " : "FAIL"} ${b.file}:${b.line}`)
    if (!same) {
      for (let i = 0; i < Math.max(slice.length, b.lines.length); i++) {
        if (slice[i] !== b.lines[i]) {
          console.log(`       line ${b.line + i}\n       live:   ${JSON.stringify(slice[i])}\n       frozen: ${JSON.stringify(b.lines[i])}`)
        }
      }
    }
  }
  console.log(`  ${blocks.size} blocks, ${liveFail} differ from the live sources`)
}

// ---------------------------------------------------------------- (2) the proof
// Every formula below is asserted against the frozen block it was cut from. The
// formula is the reference and the freeze is only where it was copied from, so
// a change in either one shows up here.
const NEEDLES = [
  ["Island.qml:37", "expr", "readonly property bool mediaPill: view === \"rest\" && mediaPlaying && !companionNeedsSetup && settings.mediaPill && !downloadPill && !systemPill && !timerPill"],
  ["Island.qml:64", "expr", "readonly property bool systemPinned: !!settings.systemMonitor"],
  ["Island.qml:65", "expr", "readonly property bool systemHot: !!settings.autoMonitorHot && systemSampler.ready && (systemSampler.temp >= 85 || systemSampler.cpu >= 95)"],
  ["Island.qml:66", "expr", "readonly property bool systemPill: view === \"rest\" && !companionNeedsSetup && systemSampler.ready && !timerPill && (systemPinned || systemHot)"],
  ["Island.qml:73", "expr", "readonly property bool timerPill: view === \"rest\" && !companionNeedsSetup && timerService.running"],
  ["Island.qml:74", "expr", "readonly property bool downloadDone: view === \"rest\" && !companionNeedsSetup && (downloadTracker.finishedName !== \"\" || packageTracker.finishedTitle !== \"\")"],
  ["Island.qml:76", "expr", "readonly property bool downloadActive: view === \"rest\" && !companionNeedsSetup && (downloadTracker.active || packageTracker.active) && !downloadDone"],
  ["Island.qml:78", "expr", "readonly property bool downloadPill: downloadDone || downloadActive"],
  ["Island.qml:426", "expr", "readonly property real clockSlot: settings.clockSeconds ? 86 : 56"],
  ["Island.qml:429", "expr", "readonly property bool pillHidden: (barHidden || (settings.hideFullscreen && outputFullscreen && !companionNeedsSetup)) && view === \"rest\""],
  ["Island.qml:494", "contains", "if (!accessoriesShown) return 100"],
  ["Island.qml:494", "contains", "return Math.max(100, Math.round(width))"],
  ["Island.qml:1137", "contains", "root.downloadDone ? 360"],
  ["Island.qml:1137", "contains", "root.downloadActive ? (root.downloadTracker.active ? 240 : 280)"],
  ["Island.qml:1137", "contains", "root.timerPill ? 240"],
  ["Island.qml:1151", "contains", "root.downloadDone ? 64"],
  ["Island.qml:1151", "contains", "root.mediaPill || root.downloadPill || root.systemPill || root.timerPill ? (root.settings.notch ? 40 : 44)"],
  ["components/Companion.qml:17", "expr", "readonly property bool needsSetup: status !== \"\" && status !== \"ok\""],
  ["companion/check.sh:3", "contains", "  ok "],
  ["companion/check.sh:3", "contains", "missing"],
  ["companion/check.sh:3", "contains", "outdated"],
  ["companion/check.sh:3", "contains", "not-enabled"],
  ["companion/check.sh:3", "contains", "menu"]
]
let proofFail = liveFail
console.log("\n(2) formulas against the frozen extract")
for (const [key, how, want] of NEEDLES) {
  const block = blocks.get(key)
  const got = block ? (how === "expr" ? block.expr : block.text) : "(no such block in the fixture)"
  const ok = how === "expr" ? got === want : got.indexOf(want) >= 0
  if (!ok) proofFail++
  console.log(`  ${ok ? "ok  " : "FAIL"} ${key}  ${ok ? "" : "\n       want: " + want + "\n       got:  " + got}`)
}

// ------------------------------------------------------------- the legacy rules
const STATUSES = ["", "ok", "missing", "outdated", "not-enabled", "menu"]   // companion/check.sh:3-8
function needsSetup(status) { return status !== "" && status !== "ok" }     // Companion.qml:17
const LEGACY_PRIORITY = { download: 90, update: 90, timer: 80, system: 70, media: 60 }

function leg(s) {
  const set = s.settings, ns = needsSetup(s.status)
  const rest = s.view === "rest"
  const timer = rest && !ns && !!s.timerRunning                                        // :73
  const downloadDone = rest && !ns && (!!s.fileFinishedName || (set.systemUpdates && !!s.pkgFinishedTitle)) // :74-75
  const downloadActive = rest && !ns                                                      // :76-77
    && ((set.downloads && !!s.fileActive) || (set.systemUpdates && !!s.pkgActive)) && !downloadDone
  const download = downloadDone || downloadActive                                         // :78
  const system = rest && !ns && !!s.systemReady && !timer                                 // :66-67
    && (set.systemMonitor || (set.autoMonitorHot && !!s.hot))
  const media = rest && !!s.mediaPlaying && set.mediaPill && !ns && !download && !system && !timer // :37
  const owner = download ? "download" : timer ? "timer" : system ? "system" : media ? "media" : null
  const width = !rest ? null : downloadDone ? 360
    : downloadActive ? (set.downloads && s.fileActive ? 240 : 280)
    : timer || system || media || download ? 240
    : ns ? 250 : null
  const height = !rest ? null : downloadDone ? 64
    : (media || download || system || timer) ? (set.notch ? 40 : 44)
    : ns ? null : (set.notch ? 36 : 40)
  return { timer, downloadDone, downloadActive, download, system, media, owner, width, height, ns }
}
// LEGACY: delete in stage 3. Only an active download or media needs an edge
// click; a finished download opens on a click anywhere (Island.qml:1287).
function legacyClickTarget(s, zone) {
  const L = leg(s)
  if (s.view !== "rest") return s.feedbackKind === "notification" ? "activateNotification" : null
  if (L.ns) return "installCompanion"
  if (L.downloadDone || (L.downloadActive && zone === "edge")) return "downloads"
  if (L.timer) return "timer"
  if (L.system) return "system"
  if (L.media && zone === "edge") return "player"
  return zone === "clock" ? "calendar" : "controls"
}

// ------------------------------------------------------------------ enumeration
// Every state goes through the adapter, and the reference reads the answer back
// out of the activities it returns: the owner of the display, the six booleans,
// the pill's box and the click target. The raw flags never reach the comparison
// on their own, which is what makes this a test of the adapter rather than a
// restating of the formulas.
const BASELINE = "74f43afe7e8e6d87"
const SETTINGS = [{ downloads: 1, systemUpdates: 1, mediaPill: 1, systemMonitor: 0, autoMonitorHot: 1, notch: 0 },
  { downloads: 0, systemUpdates: 1, mediaPill: 1, systemMonitor: 0, autoMonitorHot: 1, notch: 0 },
  { downloads: 1, systemUpdates: 0, mediaPill: 1, systemMonitor: 0, autoMonitorHot: 1, notch: 0 },
  { downloads: 1, systemUpdates: 1, mediaPill: 0, systemMonitor: 0, autoMonitorHot: 1, notch: 0 },
  { downloads: 1, systemUpdates: 1, mediaPill: 1, systemMonitor: 1, autoMonitorHot: 1, notch: 0 },
  { downloads: 1, systemUpdates: 1, mediaPill: 1, systemMonitor: 0, autoMonitorHot: 0, notch: 0 }]
const BITS = ["fileActive", "fileFinishedName", "pkgActive", "pkgFinishedTitle", "timerRunning",
  "mediaPlaying", "systemReady", "hot", "pillHidden"]
const SLOTS = ["download", "update"]

// The legacy chain had one slot for downloads and updates; the adapter splits it
// into two sources of equal priority, so the package half is the same owner.
function ownerOf(activities) {
  const top = M.visible(activities, 1)[0]
  return top ? (top.source === "update" ? "download" : top.source) : null
}

// The booleans and the pill's box, read out of the activities. `done` and the
// source of the active half are what stand in for downloadDone, downloadActive
// and the 240-versus-280 width the old chain took from the file tracker.
function derived(activities, s) {
  const has = src => activities.some(a => a.source === src)
  const slots = activities.filter(a => SLOTS.indexOf(a.source) >= 0)
  const downloadDone = slots.some(a => a.done)
  const downloadActive = slots.some(a => !a.done)
  const download = downloadDone || downloadActive
  const timer = has("timer"), system = has("system"), media = has("media")
  const set = s.settings, rest = s.view === "rest"
  const width = !rest ? null : downloadDone ? 360
    : downloadActive ? (slots.some(a => a.source === "download" && !a.done) ? 240 : 280)
    : timer || system || media || download ? 240
    : needsSetup(s.status) ? 250 : null
  const height = !rest ? null : downloadDone ? 64
    : (media || download || system || timer) ? (set.notch ? 40 : 44)
    : needsSetup(s.status) ? null : (set.notch ? 36 : 40)
  return { timer, downloadDone, downloadActive, download, system, media, width, height, ns: needsSetup(s.status) }
}

// The reference returns 0/1 for some of these: `&&` and `||` hand back their
// operands in JS, and the transcription of the QML leans on that. Coercing both
// sides is what lets the adapter, which works in real booleans, be compared with
// the frozen formulas at all.
const BOOLEAN_FIELDS = ["timer", "downloadDone", "downloadActive", "download", "system", "media"]
const rawTuple = x => [x.timer, x.downloadDone, x.downloadActive, x.download, x.system, x.media, x.width, x.height, x.ns]
const boolTuple = x => [!!x.timer, !!x.downloadDone, !!x.downloadActive, !!x.download, !!x.system, !!x.media, x.width, x.height, !!x.ns]

let states = 0, table = new Map()
const ownerMismatch = [], boolMismatch = [], clickMismatch = []
const refHash = crypto.createHash("sha256"), boolHash = crypto.createHash("sha256"), adapterHash = crypto.createHash("sha256")
for (const settings of SETTINGS) for (const status of STATUSES) for (let mask = 0; mask < (1 << BITS.length); mask++) {
  const s = { view: "rest", feedbackKind: "", settings, status }
  BITS.forEach((b, i) => { s[b] = !!(mask & (1 << i)) })
  states++
  const L = leg(s)
  const activities = M.activitiesFromState(Object.assign({}, s, { now: 1000 }))
  const D = derived(activities, s)
  const top = M.visible(activities, 1)[0]
  if (ownerOf(activities) !== L.owner) ownerMismatch.push(s)
  if (BOOLEAN_FIELDS.some(f => !!D[f] !== !!L[f]) || D.width !== L.width || D.height !== L.height) boolMismatch.push(s)
  if (top && (!top.click || top.click.view !== legacyClickTarget(s, "edge"))) clickMismatch.push(s)
  refHash.update(JSON.stringify(rawTuple(L)))
  boolHash.update(JSON.stringify(boolTuple(L)))
  adapterHash.update(JSON.stringify(boolTuple(D)))
  const key = `${L.owner}|${legacyClickTarget(s, "clock")}|${legacyClickTarget(s, "edge")}`
  table.set(key, (table.get(key) || 0) + 1)
}
const ref = refHash.digest("hex").slice(0, 16)
const refBools = boolHash.digest("hex").slice(0, 16), fromAdapter = adapterHash.digest("hex").slice(0, 16)
const hashOk = ref === BASELINE && refBools === fromAdapter
const priorityOk = ["download", "update", "timer", "system", "media"].every(src => M.LEGACY_PRIORITY[src] === LEGACY_PRIORITY[src])
console.log(`\nenumeration: ${SETTINGS.length} settings x ${STATUSES.length} companion statuses x 2^${BITS.length} = ${states} states`)
for (const [name, list] of [["display owner", ownerMismatch], ["booleans and pill box", boolMismatch], ["click target", clickMismatch]]) {
  console.log(`  ${list.length === 0 ? "ok  " : "FAIL"} ${name}: ${list.length} mismatches${list.length ? "\n       first: " + JSON.stringify(list[0]) : ""}`)
}
console.log(`  ${ref === BASELINE ? "ok  " : "FAIL"} baseline sha256: ${ref} (the frozen reference, want ${BASELINE})`)
console.log(`  ${refBools === fromAdapter ? "ok  " : "FAIL"} read as booleans: reference ${refBools}, through the adapter ${fromAdapter}`)
console.log(`  ${priorityOk ? "ok  " : "FAIL"} the adapter's priority table matches the reference`)
console.log("\ndistinct outcomes (owner | clock click | edge click):")
for (const [k, n] of [...table.entries()].sort()) console.log(`  ${k.padEnd(34)} ${n}`)
const failed = proofFail + ownerMismatch.length + boolMismatch.length + clickMismatch.length + (hashOk ? 0 : 1) + (priorityOk ? 0 : 1)
process.exit(failed === 0 ? 0 : 1)
