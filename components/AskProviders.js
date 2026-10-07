// Which AI the launcher's Ask row runs. The island offers that row only when the
// CLI it would run is actually installed: a question typed into the launcher
// should not fail because the setting points at a binary that is not there, and
// when the chosen provider is missing the other one is used instead.
//
// Pure functions over plain values, so tests/ask-providers.test.js can run this
// very file under node.

var PROVIDERS = ["claude", "chatgpt"]

// What the island ships with: Codex unless the setting says otherwise. The
// provider objects themselves (name, glyph, tile, ink) live in Island.qml.
var DEFAULT = "chatgpt"

// `setting` is settings.askAi; `available` is { claude: bool, chatgpt: bool } --
// what `command -v` found at startup.
//
// Returns the provider key to ask with, or null when neither CLI is installed
// (the caller then leaves the Ask row out). "none" stays the user's explicit
// "do not ask anything", so it is null whatever is installed.
function choose(setting, available) {
  if (setting === "none") return null
  var want = PROVIDERS.indexOf(setting) >= 0 ? setting : DEFAULT
  var other = want === "claude" ? "chatgpt" : "claude"
  var has = available || {}
  if (has[want] === true) return want
  if (has[other] === true) return other
  return null
}
