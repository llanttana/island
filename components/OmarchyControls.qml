import QtQuick
import Quickshell
import Quickshell.Io

// The control center's controls that go through Omarchy's helpers or through
// Hyprland: the power profile tabs, the brightness slider and Game Mode. They
// live here so the panel holds layout and this holds the read/write pairs.
//
// A read whose helper is missing is skipped, so an older Omarchy gets a hidden
// control rather than a knob that turns and changes nothing.
Item {
  id: controls
  required property var host

  // ---------- Power profiles (power-profiles-daemon, via Omarchy) ----------
  //
  // Omarchy remembers a profile per power source, and `autodetect` makes the
  // helper resolve ac/battery from UPower exactly as the shell does, so both
  // entry points save under the same key.
  readonly property var profileLabels: ({
    "power-saver": "Power Saver",
    "balanced": "Balanced",
    "performance": "Performance"
  })
  // Same glyphs the stock Omarchy power panel uses.
  readonly property var profileIcons: ({
    "power-saver": "󰌪",
    "balanced": "󰊚",
    "performance": "󰓅"
  })
  property var powerProfiles: []
  property string activeProfile: ""

  Process {
    id: profilesRead
    command: ["omarchy-powerprofiles-list", "--active-state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").trim().split("\n")
        var list = [], active = ""
        for (var i = 0; i < lines.length; i++) {
          var parts = lines[i].split("\t")
          var name = String(parts[0] || "").trim()
          if (name === "") continue
          list.push(name)
          if (String(parts[1] || "").trim() === "1") active = name
        }
        controls.powerProfiles = list
        controls.activeProfile = active
      }
    }
  }
  Process { id: profileWrite; onExited: profilesRead.running = true }

  function setProfile(name) {
    if (name === controls.activeProfile) return
    controls.activeProfile = name   // optimistic; profilesRead confirms
    profileWrite.command = ["omarchy-powerprofiles-set", "autodetect", name]
    profileWrite.running = true
    controls.host.announce(controls.profileLabels[name] || name)
  }

  // ---------- Brightness (the control hides when the output has none) ----------
  property bool brightnessAvailable: false
  property int brightness: 0

  Process {
    id: brightnessRead
    command: ["omarchy-brightness-display", "--monitor", controls.host.outputName]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var value = parseInt(String(text || "").trim(), 10)
        controls.brightnessAvailable = !isNaN(value)
        if (!isNaN(value)) controls.brightness = Math.max(0, Math.min(100, value))
      }
    }
    onExited: function(code) { if (code !== 0) controls.brightnessAvailable = false }
  }
  Process { id: brightnessWrite }
  Timer {
    id: brightnessDebounce
    interval: 120
    onTriggered: {
      if (brightnessWrite.running) { restart(); return }
      brightnessWrite.command = ["omarchy-brightness-display", "--no-osd", "--monitor", controls.host.outputName, controls.brightness + "%"]
      brightnessWrite.running = true
    }
  }

  // Dragging sets the value and hands the write to the debounce. A read sets
  // `brightness` directly instead, so reading the current level never writes it
  // straight back.
  function setBrightness(value) {
    controls.brightness = Math.max(0, Math.min(100, Math.round(Number(value))))
    brightnessDebounce.restart()
  }

  // ---------- Game Mode: Hyprland animations off ----------
  //
  // A config reload brings the animations back, which is the point: it is a
  // temporary "stop animating while I play" switch, not a persisted setting.
  property bool gameMode: false

  Process {
    id: gameModeRead
    command: ["hyprctl", "getoption", "animations:enabled"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: controls.gameMode = /bool:\s*false/.test(String(text || ""))
    }
  }
  Process { id: gameModeWrite; onExited: gameModeRead.running = true }

  function setGameMode(on) {
    controls.gameMode = on
    gameModeWrite.command = ["hyprctl", "eval", "hl.config({ animations = { enabled = " + (on ? "false" : "true") + " } })"]
    gameModeWrite.running = true
  }

  // Called when the panel opens.
  function refresh() {
    if (!brightnessRead.running && host.hasHelper("omarchy-brightness-display")) brightnessRead.running = true
    if (!profilesRead.running && host.hasHelper("omarchy-powerprofiles-list")) profilesRead.running = true
    if (!gameModeRead.running) gameModeRead.running = true
  }
}
