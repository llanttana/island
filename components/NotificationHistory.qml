import QtQuick
import Quickshell
import Quickshell.Io

// What the notification companion has kept, plus the actions on a row of it.
// The companion owns the files; this reads them on demand and merges in the
// banners that are still on screen, so the list matches what the user just saw.
Item {
  id: history
  required property var host

  // The live feed, set by the island. A banner still on screen counts as the
  // newest entry rather than being missing from the list.
  property var active: []
  // Newest first, as shown in the control center.
  property var rows: []

  readonly property string dir: host.home + "/.local/state/omarchy/notifications/history/"

  function key(row) {
    return String(row.timestamp) + ":" + String(row.originalId)
  }

  function refresh() {
    if (readProc.running) return
    readProc.command = ["bash", "-c", "awk 1 \"$1\"/*.json 2>/dev/null || true", "--", history.dir]
    readProc.running = true
  }

  function load(raw) {
    var out = []
    for (var j = 0; j < history.active.length; j++) {
      var live = Object.assign({}, history.active[j])
      live.isActive = true
      out.push(live)
    }
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].trim()) continue
      try { out.push(JSON.parse(lines[i])) } catch (e) { }
    }
    out.sort(function(a, b) { return Number(b.timestamp || 0) - Number(a.timestamp || 0) })
    // No cap of its own: the companion has already pruned these files to the
    // limit set in Settings, and a second, hard-coded one here would quietly
    // hide the rest of what it kept.
    history.rows = out
  }

  // Ask the companion to do something with a row: dismiss it, clear everything.
  function act(command) {
    actProc.command = command
    actProc.running = true
  }

  function commandFor(method, row) {
    return ["omarchy-shell", "notifications", method, history.key(row)]
  }

  function forget(row) {
    var k = history.key(row)
    history.rows = history.rows.filter(function(r) { return history.key(r) !== k })
  }

  function clearAll() {
    history.rows = []
    history.act(["bash", "-c", "omarchy-shell notifications dismissAll; omarchy-shell notifications clear"])
  }

  function dismiss(row) {
    history.forget(row)
    if (row.isActive) {
      history.act(history.commandFor("dismissKey", row))
    } else {
      var stem = String(row.timestamp) + "-" + String(row.originalId)
      history.act(["bash", "-c", "rm -f \"$1/$2.json\" \"$1/../images/$2\"-*", "--", history.dir, stem])
    }
  }

  Process {
    id: readProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: history.load(text)
    }
  }

  Process {
    id: actProc
    running: false
    onExited: history.refresh()
  }
}
