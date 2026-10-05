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

  // ---------- Keyboard layout (through Hyprland) ----------
  //
  // Hyprland reports more than keyboards as keyboards, and `main` is no help:
  // fcitx5's virtual keyboard takes it, and when that unbinds it lands on a
  // power button. Keep the real keyboards and read the furthest-advanced one,
  // which is the one being typed on (the same rule the stock widget uses).
  property string keyboardLayout: ""
  property string keyboardDevice: ""
  readonly property var untypedKeyboard: /^(hl-virtual-keyboard|power-button|sleep-button|lid-switch|video-bus)/
  function isTypedKeyboard(name) { return !untypedKeyboard.test(String(name || "")) }
  function pickKeyboard(boards) {
    var typed = []
    for (var i = 0; i < boards.length; i++)
      if (boards[i] && isTypedKeyboard(boards[i].name)) typed.push(boards[i])
    if (typed.length === 0) return null
    var best = typed[0]
    for (var j = 1; j < typed.length; j++)
      if (Number(typed[j].active_layout_index || 0) > Number(best.active_layout_index || 0)) best = typed[j]
    return best
  }

  Process {
    id: layoutRead
    command: ["hyprctl", "devices", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var boards = JSON.parse(String(text || "{}")).keyboards || []
          var chosen = controls.pickKeyboard(boards)
          controls.keyboardDevice = chosen ? String(chosen.name || "") : ""
          controls.keyboardLayout = chosen ? String(chosen.active_keymap || "") : ""
        } catch (e) {
          controls.keyboardDevice = ""
          controls.keyboardLayout = ""
        }
      }
    }
  }
  Process { id: layoutSwitch; onExited: if (!layoutRead.running) layoutRead.running = true }

  // The chip cycles layouts.
  function cycleLayout() {
    if (controls.keyboardDevice === "") return
    layoutSwitch.command = ["hyprctl", "switchxkblayout", controls.keyboardDevice, "next"]
    layoutSwitch.running = true
  }

  // ---------- Screen recording ----------
  property bool recording: false
  Process {
    id: recordingRead
    // Same check the stock indicator uses.
    command: ["pgrep", "--quiet", "-f", "^gpu-screen-recorder"]
    onExited: function(code) { controls.recording = code === 0 }
  }
  // Recording is started and stopped by the panel (through Omarchy's menu and
  // capture helper); this only keeps the state honest.
  function setRecording(on) { controls.recording = !!on }

  // Called when the panel opens.
  function refresh() {
    if (!brightnessRead.running && host.hasHelper("omarchy-brightness-display")) brightnessRead.running = true
    if (!profilesRead.running && host.hasHelper("omarchy-powerprofiles-list")) profilesRead.running = true
    if (!gameModeRead.running) gameModeRead.running = true
    if (!layoutRead.running) layoutRead.running = true
    if (!recordingRead.running) recordingRead.running = true
  }
}
