// Whether the island talks to a weather service at all. One switch in
// island.json, "on" unless it says "off": an island.json written before the key
// existed has no `weather` at all, and that has to keep meaning what it always
// did -- the forecast is shown.
//
// Pure functions over plain values, so tests/weather.test.js can run this very
// file under node.

var OFF = "off"

// The switch itself. Only the exact string turns the service off.
function enabled(setting) {
  return setting !== OFF
}

// What the control center's chip needs: the switch on and something to say.
// Kept here so "off means the chip is not there" is one decision and not an
// expression repeated per call site.
function chipVisible(setting, label) {
  return enabled(setting) && String(label || "") !== ""
}
