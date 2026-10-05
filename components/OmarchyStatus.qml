import QtQuick
import Quickshell
import Quickshell.Io

// The small status reads behind the control center's chips, kept out of the
// panel so the view is layout and the I/O is here: dictation from Voxtype, the
// reminder count, whether Omarchy has updates waiting, and how many agent
// sessions are running today.
//
// Every read is skipped when the helper behind it is missing, so an older
// Omarchy does not get "command not found" in the journal for a chip that would
// stay empty anyway.
Item {
  id: status
  required property var host

  property bool dictating: false
  property int reminderCount: 0
  property string reminderTooltip: ""
  property bool updatesAvailable: false
  property string updatesText: ""
  property int agentsActive: 0

  readonly property string agentsDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/agents/usage"

  // Just after the dictation chord, so the chip updates without waiting a tick.
  function refreshDictation() {
    if (!voxtypeRead.running && host.hasHelper("omarchy-voxtype-status")) voxtypeRead.running = true
  }

  // The two that change while the panel is open, on a slow tick.
  function refreshLive() {
    if (!voxtypeRead.running && host.hasHelper("omarchy-voxtype-status")) voxtypeRead.running = true
    if (!reminderRead.running && host.hasHelper("omarchy-reminder")) reminderRead.running = true
  }

  // Called when the panel opens; each read guards itself.
  function refresh() {
    if (!voxtypeRead.running && host.hasHelper("omarchy-voxtype-status")) voxtypeRead.running = true
    if (!reminderRead.running && host.hasHelper("omarchy-reminder")) reminderRead.running = true
    if (!updateRead.running && host.hasHelper("omarchy-update-available")) updateRead.running = true
    if (!agentsRead.running) agentsRead.running = true
  }

  Process {
    id: voxtypeRead
    command: ["omarchy-voxtype-status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { status.dictating = String(JSON.parse(String(text || "{}")).class || "idle") !== "idle" }
        catch (e) { status.dictating = false }
      }
    }
  }

  Process {
    id: reminderRead
    command: ["omarchy-reminder", "show", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(String(text || "{}"))
          status.reminderCount = Number(data.count || 0)
          status.reminderTooltip = String(data.tooltip || "")
        } catch (e) {
          status.reminderCount = 0
        }
      }
    }
  }

  Process {
    id: updateRead
    command: ["omarchy-update-available"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: status.updatesText = String(text || "").trim()
    }
    // The script exits 1 when there is nothing to do, 0 when updates wait.
    onExited: function(code) { status.updatesAvailable = code === 0 }
  }

  Process {
    id: agentsRead
    command: ["sh", "-c",
      'today=$(date +%F); n=0; for f in "$1"/*.json; do [ -e "$f" ] || continue; ' +
      'if jq -e --arg t "$today" \'((.todayPrompts // 0) > 0) or ((.todaySessions // 0) > 0) or (((.activeDates // []) | index($t)) != null)\' "$f" >/dev/null 2>&1; then n=$((n+1)); fi; ' +
      'done; echo $n',
      "--", status.agentsDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var n = parseInt(String(text || "").trim(), 10)
        status.agentsActive = isNaN(n) ? 0 : n
      }
    }
  }
}
