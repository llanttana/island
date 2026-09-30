import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import Quickshell.Widgets
import "../../components"

// The expanded "controls" surface: two rows of toggle pills with a round
// button at the end of each, a Levels card with vertical volume and brightness
// sliders, a System card carrying the panel indicators and the tray, and the
// recent notifications. Reads its state from the island root passed in as
// `host`.
ColumnLayout {
  id: cc
  required property var host
  property bool active: false

  // Theme palette from the island (see Island.qml).
  readonly property color accent: host.colorAccent
  readonly property color accentInk: host.colorAccentText
  readonly property color text: host.colorText
  readonly property color textMuted: host.colorMuted
  readonly property color tile: host.withAlpha(host.colorText, 0.1)
  readonly property color card: host.withAlpha(host.colorText, 0.07)
  readonly property color well: host.withAlpha(host.colorText, 0.08)
  // Hairline that defines a card against the frosted glass behind it.
  readonly property color border: host.colorBorder
  readonly property string iconFont: host.fontFamily
  readonly property int animDuration: 180 * host.motionScale

  // --- Network ---
  readonly property var netDevices: Networking.devices ? Networking.devices.values : []
  function findDevice(type) {
    var fallback = null
    for (var i = 0; i < netDevices.length; i++) {
      var d = netDevices[i]
      if (!d || d.type !== type) continue
      if (d.connected) return d
      if (!fallback) fallback = d
    }
    return fallback
  }
  readonly property var wifiDevice: findDevice(DeviceType.Wifi)
  readonly property var wiredDevice: findDevice(DeviceType.Wired)
  readonly property var wifiNetwork: {
    var nets = wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : []
    for (var i = 0; i < nets.length; i++) if (nets[i] && nets[i].connected) return nets[i]
    return null
  }

  // --- Audio ---
  readonly property var sink: Pipewire.defaultAudioSink
  readonly property bool muted: !!(sink && sink.audio && sink.audio.muted)
  readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
  readonly property var source: Pipewire.defaultAudioSource
  readonly property bool sourcePresent: !!(source && source.audio)
  readonly property bool sourceMuted: sourcePresent && source.audio.muted
  // The pill carries the device that is actually in use, not a generic label.
  readonly property string sinkName: sink ? String(sink.description || sink.nickname || sink.name || "Output") : "Output"
  readonly property string sourceName: source ? String(source.description || source.nickname || source.name || "Input") : "Input"
  readonly property real sourceVolume: sourcePresent ? Number(source.audio.volume || 0) : 0
  // Peak arrives as a linear amplitude, but some builds report dBFS; treat a
  // negative value as dB so the meter works either way.
  readonly property real sourcePeak: {
    if (!sourcePresent) return 0
    var p = Number(source.audio.peak)
    if (isNaN(p)) return 0
    if (p < 0) p = Math.pow(10, p / 20)
    return Math.max(0, Math.min(1, p))
  }
  // Meter ballistics: jump to the peak, fall back slowly, so it reads as a
  // level rather than a flickering bar.
  property real micLevel: 0
  onSourcePeakChanged: micLevel = Math.max(sourcePeak, micLevel * 0.7)

  // --- System monitor (shared with the live activity) ---
  readonly property var systemStats: host.systemStats
  // --- Countdown timer (shared with its live activity) ---
  readonly property var timer: host.timer

  // --- System: keyboard layout, recording, stay awake, tray ---
  readonly property var idleService: host.shell ? host.shell.firstPartyServiceFor("omarchy.idle") : null
  readonly property bool stayAwake: idleService ? !!idleService.stayAwake : false
  property string keyboardLayout: ""
  property string keyboardDevice: ""
  // Hyprland reports more than keyboards as keyboards, and `main` is no help:
  // fcitx5's virtual keyboard takes it, and when that unbinds it lands on a
  // power button. Keep the real keyboards and read the furthest-advanced one,
  // which is the one being typed on (the same rule the stock widget uses).
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
          var chosen = cc.pickKeyboard(boards)
          cc.keyboardDevice = chosen ? String(chosen.name || "") : ""
          cc.keyboardLayout = chosen ? String(chosen.active_keymap || "") : ""
        } catch (e) {
          cc.keyboardDevice = ""
          cc.keyboardLayout = ""
        }
      }
    }
  }
  property bool recording: false
  Process {
    id: recordingRead
    // Same check the stock indicator uses.
    command: ["pgrep", "--quiet", "-f", "^gpu-screen-recorder"]
    onExited: function(code) { cc.recording = code === 0 }
  }
  readonly property var trayItems: SystemTray.items ? SystemTray.items.values : []

  readonly property bool hasIndicators: cc.recording || cc.dnd || cc.nightOn || cc.stayAwake
    || cc.keyboardLayout !== ""

  // The rest of what the old bar carried. Everything here is a plain local
  // command, refreshed when the panel opens (and, for the two that change
  // while it is open, on a slow timer).
  property bool dictating: false
  Process {
    id: voxtypeRead
    command: ["omarchy-voxtype-status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { cc.dictating = String(JSON.parse(String(text || "{}")).class || "idle") !== "idle" }
        catch (e) { cc.dictating = false }
      }
    }
  }

  property int reminderCount: 0
  property string reminderTooltip: ""
  Process {
    id: reminderRead
    command: ["omarchy-reminder", "show", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(String(text || "{}"))
          cc.reminderCount = Number(data.count || 0)
          cc.reminderTooltip = String(data.tooltip || "")
        } catch (e) {
          cc.reminderCount = 0
        }
      }
    }
  }

  property bool updatesAvailable: false
  property string updatesText: ""
  Process {
    id: updateRead
    command: ["omarchy-update-available"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: cc.updatesText = String(text || "").trim()
    }
    // The script exits 1 when there is nothing to do, 0 when updates wait.
    onExited: function(code) { cc.updatesAvailable = code === 0 }
  }

  readonly property string agentsDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/agents/usage"
  property int agentsActive: 0
  Process {
    id: agentsRead
    command: ["sh", "-c",
      'today=$(date +%F); n=0; for f in "$1"/*.json; do [ -e "$f" ] || continue; ' +
      'if jq -e --arg t "$today" \'((.todayPrompts // 0) > 0) or ((.todaySessions // 0) > 0) or (((.activeDates // []) | index($t)) != null)\' "$f" >/dev/null 2>&1; then n=$((n+1)); fi; ' +
      'done; echo $n',
      "--", agentsDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var n = parseInt(String(text || "").trim(), 10)
        cc.agentsActive = isNaN(n) ? 0 : n
      }
    }
  }

  // Weather: the location Omarchy stores, then wttr.in for just the current
  // temperature (a few bytes, so it is cheap to refresh).
  property string weatherQuery: ""
  property string weatherText: ""
  property double weatherAt: 0
  FileView {
    id: weatherLocation
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/weather.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        var d = JSON.parse(text())
        cc.weatherQuery = (d.latitude !== undefined && d.longitude !== undefined)
          ? String(d.latitude) + "," + String(d.longitude)
          : String(d.name || "")
      } catch (e) {
        cc.weatherQuery = ""
      }
    }
    onFileChanged: reload()
  }
  Process {
    id: weatherRead
    command: ["curl", "-fsS", "--max-time", "8", "https://wttr.in/" + cc.weatherQuery + "?format=%t"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = String(text || "").trim()
        if (t === "") return
        cc.weatherText = t
        cc.weatherAt = Date.now()
      }
    }
  }
  function refreshWeather() {
    if (cc.weatherQuery === "" || weatherRead.running) return
    if (cc.weatherAt > 0 && Date.now() - cc.weatherAt < 900000) return   // 15 minutes
    weatherRead.running = true
  }

  // --- Tray menu ---
  // One opener, re-pointed as the menu is drilled into, so submenus work
  // without a stack of live objects to tear down.
  property var trayMenuItem: null
  property var trayStack: []
  QsMenuOpener { id: trayMenu }
  readonly property var trayEntries: {
    if (!cc.trayMenuItem || !trayMenu.children) return []
    return trayMenu.children.values
  }
  function openTrayMenu(item) {
    if (!item) return
    if (!item.menu) { item.activate(); return }
    // Right clicking the same icon again closes it, like every other menu.
    if (cc.trayMenuItem === item) { cc.closeTrayMenu(); return }
    cc.trayStack = []
    cc.trayMenuItem = item
    trayMenu.menu = item.menu
  }
  function enterTrayEntry(entry) {
    if (!entry) return
    if (!entry.hasChildren) { entry.triggered(); cc.closeTrayMenu(); return }
    var stack = cc.trayStack.slice()
    stack.push(entry)
    cc.trayStack = stack
    trayMenu.menu = entry
  }
  function leaveTrayEntry() {
    var stack = cc.trayStack.slice()
    if (stack.length === 0) return
    stack.pop()
    cc.trayStack = stack
    trayMenu.menu = stack.length > 0 ? stack[stack.length - 1] : cc.trayMenuItem.menu
  }
  function closeTrayMenu() {
    cc.trayStack = []
    cc.trayMenuItem = null
  }

  // Keyboard layout: the chip cycles layouts through Hyprland.
  Process { id: layoutSwitch; onExited: if (!layoutRead.running) layoutRead.running = true }
  function cycleLayout() {
    if (cc.keyboardDevice === "") return
    layoutSwitch.command = ["hyprctl", "switchxkblayout", cc.keyboardDevice, "next"]
    layoutSwitch.running = true
  }

  Timer {
    interval: 4000
    repeat: true
    running: cc.active
    onTriggered: {
      if (!voxtypeRead.running) voxtypeRead.running = true
      if (!reminderRead.running) reminderRead.running = true
    }
  }

  // --- Bluetooth ---
  readonly property var btAdapter: Bluetooth.defaultAdapter
  readonly property var btConnected: {
    var devs = Bluetooth.devices ? Bluetooth.devices.values : []
    for (var i = 0; i < devs.length; i++) if (devs[i] && devs[i].connected) return devs[i]
    return null
  }

  // --- Shell services ---
  readonly property var notifications: host.shell ? host.shell.firstPartyServiceFor("omarchy.notifications") : null
  readonly property var nightlight: host.shell ? host.shell.firstPartyServiceFor("omarchy.nightlight") : null
  readonly property bool dnd: notifications ? !!notifications.doNotDisturb : false
  readonly property bool nightOn: nightlight ? !!nightlight.enabled : false

  // --- Night light warmth ---
  readonly property int nightMin: 2500
  readonly property int nightMax: 6500
  property int nightTemp: 4000
  property int nightAttempts: 0
  Process {
    id: nightWrite
    onExited: function(code) {
      // hyprsunset may still be starting up after the toggle; retry until it
      // accepts the temperature.
      if (code !== 0 && cc.nightOn && cc.nightAttempts < 8) {
        cc.nightAttempts++
        nightApply.restart()
      }
    }
  }
  Timer { id: nightApply; interval: 220; onTriggered: cc.applyNightTemp() }
  function applyNightTemp() {
    if (!cc.nightlight) return
    if (!cc.nightOn) {
      cc.nightlight.setNightlight(true)
      cc.nightAttempts = 0
      nightApply.restart()
      return
    }
    cc.host.settings.nightTemp = cc.nightTemp
    nightWrite.command = ["hyprctl", "hyprsunset", "temperature", String(cc.nightTemp)]
    nightWrite.running = true
  }
  function setNightTemp(k) {
    cc.nightTemp = Math.max(cc.nightMin, Math.min(cc.nightMax, Math.round(k)))
    cc.nightAttempts = 0
    nightApply.restart()
  }

  // --- Game Mode: Hyprland animations off (restored by a config reload) ---
  property bool gameMode: false
  Process {
    id: gameModeRead
    command: ["hyprctl", "getoption", "animations:enabled"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: cc.gameMode = /bool:\s*false/.test(String(text || ""))
    }
  }
  Process { id: gameModeWrite; onExited: gameModeRead.running = true }
  function setGameMode(on) {
    gameMode = on
    gameModeWrite.command = ["hyprctl", "eval", "hl.config({ animations = { enabled = " + (on ? "false" : "true") + " } })"]
    gameModeWrite.running = true
  }

  // --- Power profiles (power-profiles-daemon, via Omarchy) ---
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
        cc.powerProfiles = list
        cc.activeProfile = active
      }
    }
  }
  Process { id: profileWrite; onExited: profilesRead.running = true }
  Process { id: systemAction }
  Process { id: recordingStop }
  // Anything that opens another panel or a floating terminal needs the island
  // out of the way first. While a view is open the island holds an exclusive
  // keyboard grab, and launching a second surface underneath it is what made
  // Record look frozen: the menu came up but could not take the keyboard.
  function runExternal(command) {
    cc.host.view = "rest"
    systemAction.command = command
    Qt.callLater(function() { systemAction.running = true })
  }
  function startRecording() {
    // Same door the stock indicator uses: the record menu, which offers the
    // choices (audio, webcam, region) before anything starts.
    cc.runExternal(["omarchy-menu", "toggle", "trigger.capture.screenrecord"])
  }
  function toggleDictation() {
    systemAction.command = ["voxtype", "record", "toggle"]
    systemAction.running = true
    dictationRefresh.restart()
  }
  Timer { id: dictationRefresh; interval: 700; onTriggered: if (!voxtypeRead.running) voxtypeRead.running = true }
  function showReminders() {
    cc.host.announce(cc.reminderTooltip !== "" ? cc.reminderTooltip : "Reminders")
  }
  function runUpdate() {
    cc.runExternal(["omarchy-launch-floating-terminal-with-presentation", "omarchy-update"])
  }
  function openAgents() {
    cc.runExternal(["omarchy-shell", "shell", "toggle", "omarchy.agents"])
  }
  function openWeather() {
    cc.host.view = "weather"
  }
  function stopRecording() {
    recordingStop.command = ["omarchy-capture-screenrecording", "--stop-recording"]
    recordingStop.running = true
    cc.recording = false
  }
  function toggleDnd() {
    if (!cc.notifications) return
    var next = !cc.dnd
    cc.notifications.setDoNotDisturb(next)
    cc.host.announce(next ? "Focus on" : "Focus off")
  }
  function toggleNightlight() {
    if (!cc.nightlight) return
    var next = !cc.nightOn
    cc.nightlight.setNightlight(next)
    cc.host.announce(next ? "Night light on" : "Night light off")
  }
  function toggleStayAwake() {
    if (!cc.idleService) return
    var next = !cc.stayAwake
    // Mirrors the stock indicator: set_idle_enabled(false) is what keeps the
    // lock and screensaver away.
    cc.idleService.setIdleEnabled(!next)
    cc.host.announce(next ? "Staying awake" : "Idle lock back on")
  }
  function setProfile(name) {
    if (name === cc.activeProfile) return
    cc.activeProfile = name   // optimistic; profilesRead confirms
    profileWrite.command = ["omarchy-powerprofiles-set", "autodetect", name]
    profileWrite.running = true
    cc.host.announce(cc.profileLabels[name] || name)
  }

  // --- Brightness (the Display card hides when the output has no control) ---
  property bool brightnessAvailable: false
  property int brightness: 0
  onActiveChanged: {
    if (!active) {
      // Leaving the panel must not leave a tray menu behind for next time.
      cc.closeTrayMenu()
      return
    }
    Qt.callLater(function() { cc.forceActiveFocus() })
    var storedTemp = Number(cc.host.settings.nightTemp)
    if (!isNaN(storedTemp) && storedTemp >= cc.nightMin && storedTemp <= cc.nightMax)
      cc.nightTemp = Math.round(storedTemp)
    if (!brightnessRead.running) brightnessRead.running = true
    if (!gameModeRead.running) gameModeRead.running = true
    if (!profilesRead.running) profilesRead.running = true
    if (!layoutRead.running) layoutRead.running = true
    if (!recordingRead.running) recordingRead.running = true
    if (!voxtypeRead.running) voxtypeRead.running = true
    if (!reminderRead.running) reminderRead.running = true
    if (!updateRead.running) updateRead.running = true
    if (!agentsRead.running) agentsRead.running = true
    cc.refreshWeather()
  }
  Process {
    id: brightnessRead
    command: ["omarchy-brightness-display", "--monitor", cc.host.outputName]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var value = parseInt(String(text || "").trim(), 10)
        cc.brightnessAvailable = !isNaN(value)
        if (!isNaN(value)) cc.brightness = Math.max(0, Math.min(100, value))
      }
    }
    onExited: function(code) { if (code !== 0) cc.brightnessAvailable = false }
  }
  Process { id: brightnessWrite }
  Timer {
    id: brightnessDebounce
    interval: 120
    onTriggered: {
      if (brightnessWrite.running) { restart(); return }
      brightnessWrite.command = ["omarchy-brightness-display", "--no-osd", "--monitor", cc.host.outputName, cc.brightness + "%"]
      brightnessWrite.running = true
    }
  }

  spacing: 8

  // Esc closes the control center.
  Keys.onEscapePressed: {
    if (cc.trayMenuItem !== null) cc.closeTrayMenu()
    else cc.host.view = "rest"
  }





  // ---------- Reusable pieces ----------

  // Pill toggle: icon badge (accent-filled when on), title, and state. With
  // `chevron` it reads as "opens a page" instead of "toggles in place".
  component CcTile: Rectangle {
    id: t
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property bool checked: false
    property bool available: true
    property bool chevron: false
    // When the tile is a radio (Wi-Fi, Bluetooth), the circle switches it and
    // the rest of the pill opens the list.
    property bool badgeClickable: false
    signal clicked()
    signal badgeClicked()

    Layout.fillWidth: true
    Layout.preferredWidth: 1
    Layout.preferredHeight: 52
    radius: 26
    color: cc.tile
    border.width: 1
    border.color: cc.border
    opacity: available ? 1 : 0.5
    scale: tileMouse.pressed ? 0.97 : 1
    Behavior on scale { NumberAnimation { duration: 120 * cc.host.motionScale; easing.type: Easing.OutCubic } }

    Rectangle {
      id: badge
      anchors.left: parent.left
      anchors.leftMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      width: 36; height: 36; radius: 18
      color: t.checked ? cc.accent : cc.host.withAlpha(cc.text, 0.1)
      Behavior on color { ColorAnimation { duration: cc.animDuration; easing.type: Easing.OutCubic } }
      Text {
        anchors.centerIn: parent
        text: t.icon
        color: t.checked ? cc.accentInk : cc.text
        font.family: cc.iconFont
        font.pixelSize: 17
      }
    }
    Column {
      anchors.left: badge.right
      anchors.leftMargin: 9
      anchors.right: parent.right
      anchors.rightMargin: t.chevron ? 28 : 14
      anchors.verticalCenter: parent.verticalCenter
      spacing: 1
      Text {
        width: parent.width
        text: t.title
        elide: Text.ElideRight
        color: cc.text
        font.family: "Adwaita Sans"
        font.pixelSize: 13
        font.weight: Font.DemiBold
        font.letterSpacing: -0.2
      }
      Text {
        width: parent.width
        visible: t.subtitle !== ""
        text: t.subtitle
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: t.checked ? cc.accent : cc.textMuted
        font.family: "Adwaita Sans"
        font.pixelSize: 11
      }
    }
    Text {
      visible: t.chevron
      anchors.right: parent.right
      anchors.rightMargin: 13
      anchors.verticalCenter: parent.verticalCenter
      text: "󰅂"
      color: cc.textMuted
      font.family: cc.iconFont
      font.pixelSize: 14
    }
    MouseArea {
      id: tileMouse
      anchors.fill: parent
      enabled: t.available
      cursorShape: Qt.PointingHandCursor
      onClicked: t.clicked()
    }

    MouseArea {
      anchors.fill: badge
      enabled: t.available && t.badgeClickable
      cursorShape: Qt.PointingHandCursor
      onClicked: t.badgeClicked()
    }
  }

  // Round button at the end of a toggle row; accent-filled when on.
  component CcRound: Rectangle {
    id: r
    property string icon: ""
    property bool checked: false
    signal clicked()

    Layout.preferredWidth: 52
    Layout.preferredHeight: 52
    radius: 26
    color: checked ? cc.accent : cc.tile
    border.width: checked ? 0 : 1
    border.color: cc.border
    Behavior on border.width { NumberAnimation { duration: cc.animDuration } }
    scale: roundMouse.pressed ? 0.94 : 1
    Behavior on color { ColorAnimation { duration: cc.animDuration; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 120 * cc.host.motionScale; easing.type: Easing.OutCubic } }
    Text {
      anchors.centerIn: parent
      text: r.icon
      color: r.checked ? cc.accentInk : cc.text
      font.family: cc.iconFont
      font.pixelSize: 18
    }
    MouseArea {
      id: roundMouse
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: r.clicked()
    }
  }

  // Vertical level slider: fills from the foot, glyph at the bottom, value at
  // the top. Volume and brightness sit side by side this way instead of
  // stacking two full-width cards.
  component CcVertical: ClippingRectangle {
    id: v
    property string icon: ""
    property real value: 0
    property string valueText: ""
    signal moved(real value)

    readonly property real fraction: Math.max(0, Math.min(1, v.value))
    readonly property real fillHeight: v.height * v.fraction

    Layout.preferredWidth: 52
    Layout.preferredHeight: 118
    radius: 20
    color: cc.well
    border.width: 1
    border.color: cc.border

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: v.fillHeight
      color: cc.accent
      Behavior on height {
        enabled: !vMouse.pressed
        NumberAnimation { duration: 140 * cc.host.motionScale; easing.type: Easing.OutCubic }
      }
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 12
      text: v.icon
      color: v.fillHeight > 36 ? cc.accentInk : cc.text
      font.family: cc.iconFont
      font.pixelSize: 20
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: 10
      text: v.valueText
      color: v.fillHeight > v.height - 30 ? cc.accentInk : cc.textMuted
      font.family: "Adwaita Sans"
      font.pixelSize: 11
      font.weight: Font.DemiBold
      font.features: { "tnum": 1 }
    }
    MouseArea {
      id: vMouse
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      function apply(y) { v.moved(Math.max(0, Math.min(1, 1 - y / height))) }
      onPressed: function(e) { apply(e.y) }
      onPositionChanged: function(e) { if (pressed) apply(e.y) }
      onWheel: function(e) { v.moved(Math.max(0, Math.min(1, v.value + (e.angleDelta.y > 0 ? 0.05 : -0.05)))) }
    }
  }

  // Small capsule for the status row. It is a control, not just a readout:
  // toggles stay visible in both states so switching one off does not make it
  // disappear (and with it the only way to switch it back on).
  // Tray artwork is whatever the app ships. Symbolic icons are meant to be
  // recoloured to the host's foreground (otherwise they render in their own
  // near-white or near-black fill), and the rest get a brightness lift so dark
  // artwork still reads on the card instead of looking switched off.
  component CcTrayIcon: Item {
    id: trayIconRoot
    required property var modelData
    readonly property bool symbolic: String(modelData.icon || "").split("?")[0].slice(-9) === "-symbolic"

    Image {
      id: trayIconImage
      anchors.fill: parent
      fillMode: Image.PreserveAspectFit
      sourceSize.width: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
      sourceSize.height: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
      source: String(trayIconRoot.modelData.icon || "")
      visible: false
      layer.enabled: true
    }
    MultiEffect {
      anchors.fill: trayIconImage
      source: trayIconImage
      colorization: trayIconRoot.symbolic ? 1.0 : 0.0
      colorizationColor: cc.text
      brightness: trayIconRoot.symbolic ? 0.0 : 0.3
      saturation: trayIconRoot.symbolic ? -1.0 : 0.1
    }
  }

  component CcChip: Rectangle {
    id: chip
    property string icon: ""
    property string label: ""
    property bool on: false        // toggled on: accent filled
    property bool alert: false     // recording and friends: urgent
    property bool interactive: true
    signal clicked()

    readonly property color ink: chip.alert ? cc.host.colorUrgent
      : chip.on ? cc.accentInk
      : chip.interactive ? cc.text
      : cc.textMuted

    implicitWidth: chipRow.implicitWidth + 22
    implicitHeight: 26
    radius: 13
    color: chip.alert ? cc.host.withAlpha(cc.host.colorUrgent, 0.22)
      : chip.on ? cc.accent
      : cc.well
    border.width: 1
    border.color: chip.on || chip.alert ? "transparent" : cc.border
    Behavior on color { ColorAnimation { duration: cc.animDuration; easing.type: Easing.OutCubic } }

    Row {
      id: chipRow
      anchors.centerIn: parent
      spacing: 5
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: chip.icon
        color: chip.ink
        font.family: cc.iconFont
        font.pixelSize: 13
        Behavior on color { ColorAnimation { duration: cc.animDuration } }
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: chip.label !== ""
        text: chip.label
        color: chip.ink
        font.family: "Adwaita Sans"
        font.pixelSize: 11
        font.weight: chip.on ? Font.DemiBold : Font.Normal
        Behavior on color { ColorAnimation { duration: cc.animDuration } }
      }
    }
    MouseArea {
      anchors.fill: parent
      enabled: chip.interactive
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.clicked()
    }
  }

  component CcSection: Rectangle {
    id: sec
    property string title: ""
    property bool showChevron: false
    property bool chevronOpen: false
    signal chevronClicked()
    default property alias content: body.data

    Layout.fillWidth: true
    Layout.preferredHeight: body.implicitHeight + 44
    radius: 22
    color: cc.card
    border.width: 1
    border.color: cc.border

    // Tapping the card's own background puts an open tray menu away. Declared
    // first, so every control in the card is on top of it and keeps its own
    // clicks; it only listens while a menu is actually open.
    MouseArea {
      anchors.fill: parent
      enabled: cc.trayMenuItem !== null
      onClicked: cc.closeTrayMenu()
    }

    Text {
      anchors.left: parent.left
      anchors.leftMargin: 16
      anchors.top: parent.top
      anchors.topMargin: 11
      text: sec.title
      color: cc.text
      font.family: "Adwaita Sans"
      font.pixelSize: 13
      font.weight: Font.DemiBold
      font.letterSpacing: -0.2
    }
    Rectangle {
      visible: sec.showChevron
      anchors.right: parent.right
      anchors.rightMargin: 10
      anchors.top: parent.top
      anchors.topMargin: 7
      width: 24; height: 24; radius: 12
      color: cc.well
      Text {
        anchors.centerIn: parent
        text: "󰅂"
        rotation: sec.chevronOpen ? 90 : 0
        color: cc.textMuted
        font.family: cc.iconFont
        font.pixelSize: 14
        Behavior on rotation { NumberAnimation { duration: cc.animDuration; easing.type: Easing.OutCubic } }
      }
      MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sec.chevronClicked() }
    }
    ColumnLayout {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: 36
      anchors.leftMargin: 10
      anchors.rightMargin: 10
      spacing: 6
    }
  }

  // The panel can outgrow the island (a long tray menu, a stack of
  // notifications), so the sections scroll instead of being clipped.
  Flickable {
    id: scroller
    Layout.fillWidth: true
    Layout.preferredHeight: Math.min(sections.implicitHeight, 660)
    contentHeight: sections.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
      id: sections
      width: scroller.width
      spacing: 8


      // ---------- Toggles ----------

      RowLayout {
        Layout.fillWidth: true
        spacing: 8
        CcTile {
          readonly property bool wifi: !!cc.wifiDevice
          icon: wifi ? (Networking.wifiEnabled ? "󰖩" : "󰖪") : "󰈀"
          title: wifi ? "Wi-Fi" : "Ethernet"
          subtitle: wifi
            ? (!Networking.wifiEnabled ? "Off" : cc.wifiNetwork ? cc.wifiNetwork.name : "Not connected")
            : (cc.wiredDevice && cc.wiredDevice.connected ? "Connected" : "Disconnected")
          checked: wifi ? Networking.wifiEnabled : !!(cc.wiredDevice && cc.wiredDevice.connected)
          available: wifi
          chevron: wifi
          opacity: 1
          badgeClickable: wifi
          onBadgeClicked: Networking.wifiEnabled = !Networking.wifiEnabled
          onClicked: cc.host.view = "wifi"
        }
        CcTile {
          icon: "󰍶"
          title: "Focus"
          subtitle: cc.dnd ? "On" : "Off"
          checked: cc.dnd
          available: !!cc.notifications
          onClicked: {
            var next = !cc.dnd
            cc.notifications.setDoNotDisturb(next)
            cc.host.announce(next ? "Focus on" : "Focus off")
          }
        }
        CcRound {
          icon: "󰒓"
          onClicked: cc.host.view = "settings"
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 8
        CcTile {
          icon: cc.btAdapter && cc.btAdapter.enabled ? "󰂯" : "󰂲"
          title: "Bluetooth"
          subtitle: !cc.btAdapter ? "Unavailable" : !cc.btAdapter.enabled ? "Off" : cc.btConnected ? String(cc.btConnected.name || "Connected") : "On"
          checked: !!(cc.btAdapter && cc.btAdapter.enabled)
          available: !!cc.btAdapter
          chevron: !!cc.btAdapter
          badgeClickable: !!cc.btAdapter
          onBadgeClicked: if (cc.btAdapter) cc.btAdapter.enabled = !cc.btAdapter.enabled
          onClicked: cc.host.view = "bluetooth"
        }
        CcTile {
          icon: "󰊗"
          title: "Game Mode"
          subtitle: cc.gameMode ? "On" : "Off"
          checked: cc.gameMode
          onClicked: cc.setGameMode(!cc.gameMode)
        }
        CcRound {
          icon: "󰖔"
          checked: cc.nightOn
          visible: !!cc.nightlight
          onClicked: {
            var next = !cc.nightOn
            cc.nightlight.setNightlight(next)
            // Bring the saved warmth back when the filter comes on.
            if (next) { cc.nightAttempts = 0; nightApply.restart() }
            cc.host.announce(next ? "Night light on" : "Night light off")
          }
        }
      }

      // ---------- Sound / Display ----------

      // Sliders on the left, everything you reach for on the right: the device
      // pickers and the tray. The separate System card is gone - it was a big
      // rectangle that was mostly empty space, and its buttons fit here.
      CcSection {
        title: "Controls"

        RowLayout {
          Layout.fillWidth: true
          Layout.topMargin: 2
          spacing: 10

          CcVertical {
            icon: cc.muted || cc.volume <= 0 ? "󰖁" : cc.volume < 0.34 ? "󰕿" : cc.volume < 0.67 ? "󰖀" : "󰕾"
            valueText: Math.round((cc.muted ? 0 : cc.volume) * 100) + "%"
            value: cc.muted ? 0 : cc.volume
            onMoved: function(v) {
              if (!cc.sink || !cc.sink.audio) return
              cc.sink.audio.volume = v
              if (cc.sink.audio.muted && v > 0) cc.sink.audio.muted = false
            }
          }

          // The microphone has its own slider: it is the only way to set the
          // level from a touchpad, which has no wheel to turn.
          CcVertical {
            visible: cc.sourcePresent
            icon: cc.sourceMuted ? "󰍭" : "󰍬"
            valueText: cc.sourceMuted ? "Mute" : Math.round(cc.sourceVolume * 100) + "%"
            value: cc.sourceMuted ? 0 : cc.sourceVolume
            onMoved: function(v) {
              if (!cc.sourcePresent) return
              cc.source.audio.volume = v
              if (cc.source.audio.muted && v > 0) cc.source.audio.muted = false
            }
          }

          CcVertical {
            visible: cc.brightnessAvailable
            icon: cc.brightness <= 25 ? "󰃞" : cc.brightness <= 60 ? "󰃟" : "󰃠"
            valueText: cc.brightness + "%"
            value: cc.brightness / 100
            onMoved: function(v) {
              cc.brightness = Math.round(v * 100)
              brightnessDebounce.restart()
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: 8

            // Devices as compact pills. The long names live in the list where
            // they are actually being compared, not on the card.
            RowLayout {
              Layout.fillWidth: true
              spacing: 8

              Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                radius: 11
                color: outputMouse.containsMouse ? cc.host.withAlpha(cc.text, 0.18) : cc.well
                border.width: 1
                border.color: cc.border
                Behavior on color { ColorAnimation { duration: cc.animDuration } }
                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: 9
                  anchors.rightMargin: 6
                  spacing: 6
                  Text {
                    text: cc.muted ? "󰖁" : "󰓃"
                    color: cc.muted ? cc.host.colorUrgent : cc.text
                    font.family: cc.iconFont
                    font.pixelSize: 13
                  }
                  Text {
                    Layout.fillWidth: true
                    text: cc.sinkName
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: cc.text
                    font.family: "Adwaita Sans"
                    font.pixelSize: 11
                  }
                  Text {
                    text: "󰅂"
                    color: cc.textMuted
                    font.family: cc.iconFont
                    font.pixelSize: 12
                  }
                }
                // The body opens the Audio page; the glyph is the mute switch.
                MouseArea {
                  id: outputMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: cc.host.view = "audio"
                }
                MouseArea {
                  anchors.left: parent.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  width: 26
                  enabled: !!cc.sink
                  cursorShape: Qt.PointingHandCursor
                  onClicked: if (cc.sink) cc.sink.audio.muted = !cc.sink.audio.muted
                }
              }

              Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                radius: 11
                color: inputMouse.containsMouse ? cc.host.withAlpha(cc.text, 0.18) : cc.well
                border.width: 1
                border.color: cc.border
                opacity: cc.sourcePresent ? 1 : 0.5
                Behavior on color { ColorAnimation { duration: cc.animDuration } }
                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: 9
                  anchors.rightMargin: 6
                  spacing: 6
                  Text {
                    text: cc.sourceMuted ? "󰍭" : "󰍬"
                    color: cc.sourceMuted ? cc.host.colorUrgent : cc.text
                    font.family: cc.iconFont
                    font.pixelSize: 13
                  }
                  Text {
                    Layout.fillWidth: true
                    text: cc.sourceName
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: cc.sourceMuted ? cc.host.colorUrgent : cc.text
                    font.family: "Adwaita Sans"
                    font.pixelSize: 11
                  }
                  Text {
                    text: "󰅂"
                    color: cc.textMuted
                    font.family: cc.iconFont
                    font.pixelSize: 12
                  }
                }
                MouseArea {
                  id: inputMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: cc.host.view = "audio"
                }
                // The glyph is the mute switch, so the pill does both jobs.
                MouseArea {
                  anchors.left: parent.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  width: 26
                  enabled: cc.sourcePresent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: cc.source.audio.muted = !cc.source.audio.muted
                }
              }
            }

            // What the old bar used to show at a glance. It now sits under the
            // device pills, inside the card, instead of hanging below it.
            Flow {
              id: chipFlow
              Layout.fillWidth: true
              Layout.topMargin: 2
              Layout.preferredHeight: chipFlow.implicitHeight
              spacing: 6
              visible: chipFlow.implicitHeight > 0

              CcChip {
                visible: cc.keyboardLayout !== ""
                icon: "󰌌"
                label: cc.keyboardLayout.replace(/\s*\(.*\)$/, "")
                onClicked: cc.cycleLayout()
              }
              CcChip {
                icon: "󰻂"
                label: cc.recording ? "REC" : "Record"
                alert: cc.recording
                onClicked: cc.recording ? cc.stopRecording() : cc.startRecording()
              }
              CcChip {
                icon: "󰅶"
                label: "Awake"
                on: cc.stayAwake
                onClicked: cc.toggleStayAwake()
              }
              CcChip {
                visible: cc.dictating
                icon: "󰍬"
                label: "Dictating"
                on: true
                onClicked: cc.toggleDictation()
              }
              CcChip {
                visible: cc.reminderCount > 0
                icon: "󰃰"
                label: cc.reminderCount > 1 ? cc.reminderCount + " reminders" : "1 reminder"
                on: true
                onClicked: cc.showReminders()
              }
              CcChip {
                visible: cc.updatesAvailable
                icon: "󰚰"
                label: "Update"
                on: true
                onClicked: cc.runUpdate()
              }
              CcChip {
                visible: cc.agentsActive > 0
                icon: "󰚩"
                label: cc.agentsActive > 1 ? cc.agentsActive + " agents" : "1 agent"
                on: true
                onClicked: cc.openAgents()
              }
              CcChip {
                visible: cc.weatherText !== ""
                icon: "󰖐"
                label: cc.weatherText
                onClicked: cc.openWeather()
              }
              CcChip {
                visible: cc.systemStats.ready
                icon: "󰍛"
                label: Math.round(cc.systemStats.cpu) + "%"
                  + (cc.systemStats.temp > 0 ? " · " + cc.systemStats.temp + "°" : "")
                onClicked: cc.host.view = "system"
              }
              CcChip {
                icon: "󰔛"
                label: cc.timer.running ? cc.timer.formatted() : "Timer"
                on: cc.timer.running
                onClicked: cc.host.view = "timer"
              }
            }

            RowLayout {
              Layout.fillWidth: true
              visible: cc.trayItems.length > 0
              spacing: 6
              Text {
                text: "Tray"
                color: cc.textMuted
                font.family: "Adwaita Sans"
                font.pixelSize: 11
              }
              Item { Layout.fillWidth: true }
              Repeater {
                model: cc.trayItems
                delegate: Item {
                  id: trayCell
                  required property var modelData
                  Layout.preferredWidth: 24
                  Layout.preferredHeight: 24
                  CcTrayIcon {
                    anchors.fill: parent
                    modelData: trayCell.modelData
                  }
                  // Left click opens the app, right click its menu - and for
                  // the handful of items that declare themselves menu-only
                  // (Steam does), left click opens the menu too, because that is
                  // the only action such an item offers.
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: function(mouse) {
                      if (mouse.button === Qt.RightButton) cc.openTrayMenu(trayCell.modelData)
                      else if (mouse.button === Qt.MiddleButton) trayCell.modelData.secondaryActivate()
                      else if (trayCell.modelData.onlyMenu) cc.openTrayMenu(trayCell.modelData)
                      else trayCell.modelData.activate()
                    }
                    onWheel: function(wheel) { trayCell.modelData.scroll(wheel.angleDelta.y, false) }
                  }
                }
              }
            }

            // Night-light warmth, revealed while the filter is on.
            RowLayout {
              Layout.fillWidth: true
              visible: cc.nightOn
              spacing: 8
              IslandSlider {
                host: cc.host
                Layout.fillWidth: true
                icon: "󰟸"
                value: (cc.nightTemp - cc.nightMin) / (cc.nightMax - cc.nightMin)
                valueText: cc.nightTemp + " K"
                onMoved: function(v) {
                  cc.setNightTemp(cc.nightMin + v * (cc.nightMax - cc.nightMin))
                }
              }
            }
          }
        }

        // A tray item's own menu, in place. Right click opens it (and closes it
        // again); entries with children drill in; there is an explicit close row
        // because a menu you can only leave by accident is a trap.
        Flickable {
          id: trayMenuScroll
          Layout.fillWidth: true
          Layout.preferredHeight: cc.trayMenuItem ? Math.min(trayMenuColumn.implicitHeight, 300) : 0
          contentHeight: trayMenuColumn.implicitHeight
          clip: true
          visible: cc.trayMenuItem !== null
          boundsBehavior: Flickable.StopAtBounds

          ColumnLayout {
            id: trayMenuColumn
            width: trayMenuScroll.width
            spacing: 0

            Rectangle {
              visible: cc.trayMenuItem !== null
              Layout.fillWidth: true
              Layout.topMargin: 6
              Layout.preferredHeight: 30
              radius: 10
              color: closeMouse.containsMouse ? cc.well : "transparent"
              Row {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "󰅖"
                  color: cc.textMuted
                  font.family: cc.iconFont
                  font.pixelSize: 13
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Close menu"
                  color: cc.text
                  font.family: "Adwaita Sans"
                  font.pixelSize: 12
                }
              }
              MouseArea {
                id: closeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: cc.closeTrayMenu()
              }
            }

            Rectangle {
              visible: cc.trayMenuItem !== null && cc.trayStack.length > 0
              Layout.fillWidth: true
              Layout.preferredHeight: 30
              radius: 10
              color: backMouse.containsMouse ? cc.well : "transparent"
              Row {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "󰅁"
                  color: cc.textMuted
                  font.family: cc.iconFont
                  font.pixelSize: 13
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: cc.trayStack.length > 0 ? String(cc.trayStack[cc.trayStack.length - 1].text || "") : ""
                  color: cc.text
                  font.family: "Adwaita Sans"
                  font.pixelSize: 12
                }
              }
              MouseArea {
                id: backMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: cc.leaveTrayEntry()
              }
            }

            Repeater {
              model: cc.trayMenuItem ? cc.trayEntries : []
              delegate: Rectangle {
                id: trayRow
                required property var modelData
                readonly property bool separator: modelData.isSeparator === true
                Layout.fillWidth: true
                Layout.preferredHeight: separator ? 9 : 30
                radius: 10
                color: !separator && trayMouse.containsMouse ? cc.well : "transparent"

                Rectangle {
                  visible: trayRow.separator
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.leftMargin: 10
                  anchors.rightMargin: 10
                  height: 1
                  color: cc.border
                }
                RowLayout {
                  visible: !trayRow.separator
                  anchors.fill: parent
                  anchors.leftMargin: 10
                  anchors.rightMargin: 10
                  spacing: 8
                  Image {
                    visible: String(trayRow.modelData.icon || "") !== ""
                    Layout.preferredWidth: 16
                    Layout.preferredHeight: 16
                    source: trayRow.modelData.icon
                    sourceSize.width: 32
                    sourceSize.height: 32
                    fillMode: Image.PreserveAspectFit
                  }
                  Text {
                    Layout.fillWidth: true
                    text: String(trayRow.modelData.text || "")
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: trayRow.modelData.enabled ? cc.text : cc.textMuted
                    font.family: "Adwaita Sans"
                    font.pixelSize: 12
                  }
                  Text {
                    visible: trayRow.modelData.hasChildren === true
                    text: "󰅂"
                    color: cc.textMuted
                    font.family: cc.iconFont
                    font.pixelSize: 13
                  }
                }
                MouseArea {
                  id: trayMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  enabled: !trayRow.separator && trayRow.modelData.enabled
                  cursorShape: Qt.PointingHandCursor
                  onClicked: cc.enterTrayEntry(trayRow.modelData)
                }
              }
            }
          }
        }
      }

      CcSection {
        title: "Power"
        visible: cc.powerProfiles.length > 0

        RowLayout {
          Layout.fillWidth: true
          spacing: 6

          Repeater {
            model: cc.powerProfiles
            delegate: Rectangle {
              id: profile
              required property var modelData
              readonly property bool selected: modelData === cc.activeProfile

              Layout.fillWidth: true
              Layout.preferredHeight: 38
              radius: 13
              color: profile.selected ? cc.accent : cc.well
              scale: profileMouse.pressed ? 0.97 : 1
              Behavior on color { ColorAnimation { duration: cc.animDuration; easing.type: Easing.OutCubic } }
              Behavior on scale { NumberAnimation { duration: 120 * cc.host.motionScale; easing.type: Easing.OutCubic } }

              Row {
                anchors.centerIn: parent
                spacing: 6
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: cc.profileIcons[profile.modelData] || ""
                  color: profile.selected ? cc.accentInk : cc.text
                  font.family: cc.iconFont
                  font.pixelSize: 14
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: cc.profileLabels[profile.modelData] || profile.modelData
                  color: profile.selected ? cc.accentInk : cc.text
                  font.family: "Adwaita Sans"
                  font.pixelSize: 12
                  font.weight: profile.selected ? Font.DemiBold : Font.Normal
                }
              }

              MouseArea {
                id: profileMouse
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: cc.setProfile(profile.modelData)
              }
            }
          }
        }
      }

      // ---------- Notifications ----------

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: notificationBody.implicitHeight + 18
        radius: 22
        color: cc.card
        border.width: 1
        border.color: cc.border

        ColumnLayout {
          id: notificationBody
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: 10
          spacing: 8

          RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            Layout.topMargin: 2
            Text {
              text: "Notifications"
              color: cc.text
              font.family: "Adwaita Sans"
              font.pixelSize: 13
              font.weight: Font.DemiBold
              font.letterSpacing: -0.2
            }
            Item { Layout.fillWidth: true }
            // iOS's grey capsule button.
            Rectangle {
              visible: cc.host.history.length > 0
              implicitWidth: clearLabel.implicitWidth + 20
              implicitHeight: 22
              radius: 12
              color: clearMouse.containsMouse ? cc.host.withAlpha(cc.text, 0.16) : cc.well
              Behavior on color { ColorAnimation { duration: cc.animDuration } }
              Text {
                id: clearLabel
                anchors.centerIn: parent
                text: "Clear"
                color: cc.text
                font.family: "Adwaita Sans"
                font.pixelSize: 11
                font.weight: Font.Medium
              }
              MouseArea {
                id: clearMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: cc.host.clearAllNotifications()
              }
            }
          }

          Text {
            visible: cc.host.history.length === 0
            Layout.fillWidth: true
            Layout.topMargin: 4
            Layout.bottomMargin: 8
            horizontalAlignment: Text.AlignHCenter
            text: "No notifications"
            color: cc.textMuted
            font.family: "Adwaita Sans"
            font.pixelSize: 12
          }

          ListView {
            visible: cc.host.history.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 190)
            clip: true
            spacing: 8
            boundsBehavior: Flickable.StopAtBounds
            model: cc.host.history
            delegate: Rectangle {
              id: note
              required property var modelData
              readonly property string appName: String(modelData.app || modelData.summary || "?")
              width: ListView.view.width
              height: noteBody.implicitHeight + 20
              radius: 20
              color: noteMouse.containsMouse ? cc.host.withAlpha(cc.text, 0.12) : cc.card

              MouseArea {
                id: noteMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // Opens the app the notification came from (see the host).
                onClicked: cc.host.activateNotification(note.modelData)
              }
              // The notification's image or app icon; a letter avatar when
              // there's none (or it fails to load).
              ClippingRectangle {
                id: avatar
                // A live image handle dies with the shell; fall back to the app
                // icon (then the letter) when it no longer loads.
                property bool imageFailed: false
                readonly property string source: cc.host.notificationIconSource(note.modelData, imageFailed)
                readonly property var brand: cc.host.notificationBrand(note.modelData)
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.top: parent.top
                anchors.topMargin: 10
                width: 30; height: 30; radius: 8
                color: brand ? brand.tile
                  : noteIcon.status === Image.Ready ? "transparent" : cc.host.withAlpha(cc.accent, 0.18)
                Image {
                  id: noteIcon
                  anchors.fill: parent
                  source: avatar.source
                  sourceSize.width: 60
                  sourceSize.height: 60
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  visible: status === Image.Ready
                  onStatusChanged: if (status === Image.Error) avatar.imageFailed = true
                }
                Text {
                  anchors.centerIn: parent
                  visible: noteIcon.status !== Image.Ready
                  text: avatar.brand ? avatar.brand.glyph : note.appName.charAt(0).toUpperCase()
                  // Not the accent: with a white accent the letter would disappear
                  // into its own tint. The theme foreground reads on that tint.
                  color: avatar.brand ? avatar.brand.ink : cc.text
                  font.family: avatar.brand ? "JetBrainsMono Nerd Font" : "Adwaita Sans"
                  font.pixelSize: avatar.brand ? 20 : 14
                  font.weight: Font.DemiBold
                }
              }
              Column {
                id: noteBody
                anchors.left: avatar.right
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.rightMargin: 32
                anchors.top: parent.top
                anchors.topMargin: 12
                spacing: 2
                // Like iOS's Notification Center: the title with the time on the
                // same line (the icon already says which app).
                Item {
                  width: parent.width
                  height: noteTitle.height
                  Text {
                    id: noteTitle
                    anchors.left: parent.left
                    anchors.right: noteAge.left
                    anchors.rightMargin: 8
                    text: cc.host.notificationTitle(note.modelData)
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: cc.text
                    font.family: "Adwaita Sans"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    font.letterSpacing: -0.2
                  }
                  Text {
                    id: noteAge
                    anchors.right: parent.right
                    anchors.baseline: noteTitle.baseline
                    text: cc.host.notificationAge(note.modelData.timestamp)
                    textFormat: Text.PlainText
                    color: cc.textMuted
                    font.family: "Adwaita Sans"
                    font.pixelSize: 11
                  }
                }
                Text {
                  width: parent.width
                  // Apps often send markup in the body rather than setting the
                  // markup hint (Telegram sends "<b>Name</b>\nMessage"), so render
                  // anything that looks like markup as styled text and everything
                  // else literally.
                  readonly property string rawBody: String(note.modelData.body || "")
                  text: rawBody
                  visible: text !== ""
                  textFormat: /<[a-z][^>]*>/i.test(rawBody) ? Text.StyledText : Text.PlainText
                  wrapMode: Text.Wrap
                  maximumLineCount: 3
                  elide: Text.ElideRight
                  color: cc.host.withAlpha(cc.text, 0.72)
                  font.family: "Adwaita Sans"
                  font.pixelSize: 12
                }
              }
              Text {
                anchors.right: parent.right
                anchors.rightMargin: 13
                anchors.top: parent.top
                anchors.topMargin: 12
                text: "󰅖"
                color: noteCloseMouse.containsMouse ? cc.text : cc.textMuted
                font.family: cc.iconFont
                font.pixelSize: 13
                MouseArea { id: noteCloseMouse; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; onClicked: cc.host.dismissNotification(note.modelData) }
              }
            }
          }
        }
      }
    }
  }

}
