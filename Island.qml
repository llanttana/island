import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Wayland
import qs.Commons
import "components"
import "views"
import "file:///usr/share/omarchy/shell/plugins/clipboard/ClipboardHistory.js" as ClipboardHistory
import "companion/guilhermerisu.notifications/NotificationLogic.js" as NotificationLogic

Item {
  id: root
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property var barWidgetRegistry: null
  property var barConfig: ({})
  property string omarchyPath: ""

  readonly property var media: shell ? shell.firstPartyServiceFor("omarchy.media") : null
  readonly property var player: media ? media.activePlayer : null
  readonly property bool mediaPlaying: !!(player && player.isPlaying)
  readonly property string reportedArt: player && player.trackArtUrl ? String(player.trackArtUrl) : ""
  readonly property string mediaTitle: player ? String(player.trackTitle || "") : ""
  property string keptArt: ""
  property string keptArtTitle: ""
  onReportedArtChanged: if (reportedArt) { keptArt = reportedArt; keptArtTitle = mediaTitle }
  onMediaTitleChanged: if (mediaTitle !== keptArtTitle) { keptArt = reportedArt; keptArtTitle = mediaTitle }
  readonly property string mediaArt: reportedArt || (mediaTitle === keptArtTitle ? keptArt : "")
  readonly property bool mediaPill: view === "rest" && mediaPlaying && !companionNeedsSetup && settings.mediaPill && !downloadPill

  property string askQuestion: ""
  readonly property var askProviders: ({
    claude: { name: "Claude", cli: "claude", glyph: "\uec82", tile: "#d97757", ink: "#ffffff" },
    chatgpt: { name: "Codex", cli: "codex", glyph: "\uec81", tile: "#f2f2f2", ink: "#000000" }
  })
  readonly property var askProvider: settings.askAi === "none" ? null : askProviders[settings.askAi] || askProviders.chatgpt
  function ask(question) {
    question = String(question || "").trim()
    if (!question || !askProvider) return
    askQuestion = question
    view = "answer"
  }

  readonly property Item downloadTracker: downloadWatcher
  Downloads { id: downloadWatcher; enabled: root.settings.downloads }
  readonly property Item packageTracker: packageWatcher
  PackageUpdates { id: packageWatcher; enabled: root.settings.systemUpdates }
  readonly property bool downloadDone: view === "rest" && !companionNeedsSetup
    && (downloadTracker.finishedName !== "" || packageTracker.finishedTitle !== "")
  readonly property bool downloadActive: view === "rest" && !companionNeedsSetup
    && (downloadTracker.active || packageTracker.active) && !downloadDone
  readonly property bool downloadPill: downloadDone || downloadActive
  Process { id: downloadOpener }
  function openDownloads() {
    if (!downloadTracker.active && downloadTracker.finishedName === "") {
      packageTracker.dismissFinished()
      return
    }
    var path = downloadDone ? downloadTracker.finishedPath : downloadTracker.folder
    downloadTracker.dismissFinished()
    downloadOpener.command = ["sh", "-c", '[ -e "$1" ] && exec xdg-open "$1"; exec xdg-open "$(dirname "$1")"', "sh", path]
    downloadOpener.startDetached()
  }

  ColorQuantizer {
    id: coverColors
    source: root.mediaArt
    depth: 2
    rescaleSize: 64
  }
  readonly property color mediaTint: {
    var best = null, bestScore = -1
    var colors = coverColors.colors || []
    for (var i = 0; i < colors.length; i++) {
      var c = colors[i]
      var score = c.hsvSaturation * 0.7 + c.hsvValue * 0.3
      if (score > bestScore) { bestScore = score; best = c }
    }
    if (!best || best.hsvSaturation < 0.12) return colorAccent
    return Qt.hsva(best.hsvHue, Math.min(1, best.hsvSaturation), Math.max(0.75, best.hsvValue), 1)
  }
  readonly property real volume: Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio
    ? Pipewire.defaultAudioSink.audio.volume : -1
  readonly property bool muted: !!(Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio
    && Pipewire.defaultAudioSink.audio.muted)
  readonly property string wantedOutput: String(barConfig.output || "DP-1")
  readonly property string outputName: {
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++)
      if (screens[i].name === wantedOutput) return wantedOutput
    var focused = Hyprland.focusedMonitor
    if (focused && focused.name) return String(focused.name)
    return screens.length ? String(screens[0].name) : ""
  }
  // The Hyprland monitor the pill is showing on, and whether a window there is
  // fullscreen — used to slide the pill away for fullscreen video and games.
  readonly property var islandMonitor: {
    var list = Hyprland.monitors.values
    for (var i = 0; i < list.length; i++)
      if (String(list[i].name) === outputName) return list[i]
    return Hyprland.focusedMonitor
  }
  readonly property bool outputFullscreen: {
    var monitor = islandMonitor
    return !!(monitor && monitor.activeWorkspace && monitor.activeWorkspace.hasFullscreen)
  }
  readonly property string home: Quickshell.env("HOME")

  readonly property QtObject settings: settingsData
  FileView {
    path: root.home + "/.config/omarchy/island.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onAdapterUpdated: writeAdapter()
    onLoadFailed: function(error) {
      if (error !== FileViewError.FileNotFound) return
      writeAdapter()
      Qt.callLater(reload)
    }
    JsonAdapter {
      id: settingsData
      property real motionScale: 1.5
      property bool hoverLift: true
      property bool clock24h: true
      property bool mediaPill: true
      property bool volumeHud: true
      property int bannerSeconds: 5
      property bool notch: false
      property bool downloads: true
      property bool clipboard: true
      property bool systemUpdates: true
      property bool hideFullscreen: true
      property string askAi: "chatgpt"
    }
  }
  readonly property string feedPath: home + "/.local/state/omarchy/island-feed.json"
  readonly property string historyDir: home + "/.local/state/omarchy/notifications/history/"
  property string themeName: ""

  readonly property var clockDate: clock.date
  property string view: "rest"
  readonly property bool notificationPill: view === "feedback" && feedbackKind === "notification"
  readonly property bool volumePill: view === "feedback" && feedbackKind === "volume"
  readonly property bool clipboardPill: view === "feedback" && feedbackKind === "clipboard"

  property var lastClip: null
  property string lastClipKey: ""
  property bool clipSeeded: false
  property double clipboardQuietUntil: 0
  FileView {
    path: root.home + "/.local/state/omarchy/clipboard-history.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.clipboardChanged(text())
  }
  function isHtml(text) {
    return /^\s*<(img|meta|html|!doctype|body|div|span|p|a|picture|figure|table)\b/i.test(String(text || ""))
  }
  function clipboardChanged(raw) {
    var history = ClipboardHistory.parseHistory(raw)
    var top = history.length ? history[0] : null
    if (top && top.type === "text" && isHtml(top.text) && history.length > 1 && history[1].type === "image")
      top = history[1]
    var key = top ? ClipboardHistory.entryKey(top) : ""
    var fresh = clipSeeded && key !== "" && key !== lastClipKey
    lastClipKey = key
    clipSeeded = true
    if (!fresh || !settings.clipboard || Date.now() < clipboardQuietUntil) return
    lastClip = top
    showFeedback("", 2200, "clipboard")
  }

  property bool surfaceContentReady: false
  property string feedback: ""
  property string feedbackKind: ""
  property var activeNotifications: []
  property var lastNotification: null
  property var surfaceNames: []
  function registerSurface(name) {
    if (surfaceNames.indexOf(name) === -1) surfaceNames = surfaceNames.concat([name])
  }
  readonly property bool surfaceOpen: surfaceNames.indexOf(view) !== -1
  property var history: []
  property string lastNotificationKey: ""
  property bool initialized: false
  readonly property bool barHidden: barOffFlag.count > 0
  FolderListModel {
    id: barOffFlag
    folder: "file://" + root.home + "/.local/state/omarchy/toggles"
    nameFilters: ["bar-off"]
    showDirs: false
    showHidden: true
  }
  readonly property int barSize: 0
  readonly property string position: "top"
  readonly property string fontFamily: "monospace"
  // ---------- Palette ----------
  //
  // The pill carries the theme's own background, frosted by the compositor (see
  // the layer rule in ~/.config/hypr/looknfeel.lua), so its text colours are
  // simply the theme's.
  //
  // The accent is deliberately neutral white instead of a palette hue: the
  // shell's Color.accent is often the same colour as the foreground (kanagawa:
  // both #dcd7ba), which flattens every "on" state into the text colour, and
  // borrowing a hue from the palette reads as decoration rather than state. On
  // a light theme white would disappear, so it flips to near-black.

  // Frosted glass: the theme background at partial alpha.
  readonly property color colorBackground: withAlpha(Color.background, 0.72)
  readonly property color colorText: Color.foreground
  // A dimmed foreground rather than the theme's `muted`: the pill now sits on
  // the theme's own background at partial alpha, and themes whose muted is a
  // near-background colour (kanagawa: #54546D) become unreadable there.
  readonly property color colorMuted: withAlpha(colorText, 0.62)
  readonly property color colorAccent: luminance(Color.background) < 0.5 ? "#ffffff" : "#14141a"
  readonly property color colorAccentText: contrastOn(colorAccent)
  readonly property color colorUrgent: Color.urgent
  readonly property color colorSurface: withAlpha(colorText, 0.07)
  // Hairlines that give the glass cards an edge without a heavy outline.
  readonly property color colorBorder: withAlpha(colorText, 0.12)
  // The pill's own text now follows the theme, so the ink is just the text.
  readonly property color ink: colorText

  function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function luminance(x) { return 0.2126 * x.r + 0.7152 * x.g + 0.0722 * x.b }
  function contrastOn(c) {
    var l = luminance(c)
    var onDark = Math.abs(l - luminance(Color.background)) > Math.abs(l - luminance(Color.foreground))
    return onDark ? Color.background : Color.foreground
  }

  readonly property real motionScale: settings.motionScale > 0 ? settings.motionScale : 1.5

  // Small status accessories (workspace dots, battery) sit beside the clock
  // only in the plain resting state, so they never crowd a live activity.
  readonly property bool accessoriesShown: view === "rest" && !mediaPill && !downloadPill && !companionNeedsSetup
  // Room reserved for the clock text so the accessories never crowd it.
  readonly property real clockSlot: 56
  // The pill slides off-screen while a window is fullscreen (the widget can be
  // turned off in Settings). The manual `Super + Shift + Space` toggle stays.
  readonly property bool pillHidden: (barHidden || (settings.hideFullscreen && outputFullscreen && !companionNeedsSetup)) && view === "rest"

  // ---------- Status accessories on the resting pill ----------

  // Battery (UPower): charge glyph + percentage, accent on wall power, urgent
  // while low and draining. Hidden entirely when there is no battery.
  readonly property var batteryDevice: UPower.displayDevice
  readonly property bool batteryPresent: !!(batteryDevice && batteryDevice.isPresent)
  readonly property real batteryFraction: batteryPresent
    ? Math.max(0, Math.min(1, Number(batteryDevice.percentage) || 0)) : 0
  readonly property int batteryPercent: Math.round(batteryFraction * 100)
  readonly property bool batteryDischarging: batteryPresent && batteryDevice.state === UPowerDeviceState.Discharging
  readonly property bool batteryFull: batteryPresent && batteryDevice.state === UPowerDeviceState.FullyCharged
  readonly property bool batteryLow: batteryDischarging && batteryPercent <= 20
  readonly property color batteryTint: batteryLow ? colorUrgent : UPower.onBattery ? ink : colorAccent
  function batteryIcon() {
    if (!batteryPresent) return ""
    // Same glyph set the stock Omarchy power panel uses.
    var dischargingIcons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
    var chargingIcons = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
    var index = Math.max(0, Math.min(9, Math.floor(batteryFraction * 10)))
    if (batteryFull) return "󰂅"
    return UPower.onBattery ? dischargingIcons[index] : chargingIcons[index]
  }

  // Workspaces: the same set the stock bar shows (1–5, plus any occupied
  // workspace up to 10). Clicking a dot switches to that workspace.
  readonly property var workspaceIds: {
    var list = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && list.indexOf(id) === -1) list.push(id)
    }
    list.sort(function(a, b) { return a - b })
    return list
  }
  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) if (values[i].id === id) return values[i]
    return null
  }
  function focusWorkspace(id) {
    Hyprland.dispatch('hl.dsp.focus({ workspace = "' + id + '" })')
  }
  readonly property int workspaceDotSize: 5
  readonly property int workspaceDotGap: 4
  readonly property real workspaceDotsWidth: {
    var count = workspaceIds.length
    return count > 0 ? count * workspaceDotSize + (count - 1) * workspaceDotGap : 0
  }

  // Width the resting pill needs for the clock plus whichever accessories are
  // actually present, so the centred clock never collides with them.
  TextMetrics {
    id: batteryMetrics
    font.family: "Adwaita Sans"
    font.pixelSize: 12
    font.weight: Font.DemiBold
    text: root.batteryPercent + "%"
  }
  readonly property real batteryBadgeWidth: batteryPresent ? 13 + 3 + batteryMetrics.width + 4 : 0
  readonly property real restWidth: {
    if (!accessoriesShown) return 100
    var width = 24 + clockSlot
    if (workspaceDotsWidth > 0) width += workspaceDotsWidth + 10
    if (batteryBadgeWidth > 0) width += batteryBadgeWidth + 10
    return Math.max(100, Math.round(width))
  }

  function notificationIconSource(row, appIconOnly) {
    if (!row) return ""
    if (notificationAgent(row)) return ""
    var value = String((appIconOnly ? "" : row.image) || row.appIcon || "")
    if (value === "") return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return "file://" + value
    return Quickshell.iconPath(value, true)
  }

  function notificationAgent(row) {
    var summary = String(row.summary || "")
    if (summary === "Claude Code") return "claude"
    var fromTerminal = /ghostty|kitty|alacritty|foot|wezterm/i.test(String(row.appIcon || "") + " " + String(row.app || ""))
    if (summary === "Codex" || (fromTerminal && /^(Ghostty|kitty|Alacritty|foot|WezTerm)$/.test(summary))) return "codex"
    return ""
  }
  readonly property var notificationBrands: ({
    claude: { glyph: "\uec82", tile: "#d97757", ink: "#ffffff" },
    codex: { glyph: "\uec81", tile: "#f2f2f2", ink: "#000000" }
  })
  function notificationBrand(row) {
    var agent = row ? notificationAgent(row) : ""
    return agent ? notificationBrands[agent] : null
  }
  function notificationTitle(row) {
    if (!row) return "Notification"
    if (notificationAgent(row) === "codex") return "Codex"
    return String(row.summary || row.app || "Notification")
  }
  function notificationAge(timestamp) {
    var ms = Date.now() - Number(timestamp || 0)
    if (!timestamp || ms < 60000) return "now"
    if (ms < 3600000) return Math.floor(ms / 60000) + "m ago"
    if (ms < 86400000) return Math.floor(ms / 3600000) + "h ago"
    return Qt.formatDateTime(new Date(Number(timestamp)), "d MMM")
  }

  function surfaceOpenFor(v) { return surfaceNames.indexOf(v) !== -1 }

  FileView {
    path: root.home + "/.local/state/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var name = text().trim()
      var previous = root.themeName
      root.themeName = name
      if (previous !== "" && name !== "" && name !== previous) root.announce("Theme · " + name)
    }
    onFileChanged: reload()
  }

  onViewChanged: {
    surfaceContentReady = false
    if (surfaceOpenFor(view)) surfaceRevealTimer.restart()
    else surfaceRevealTimer.stop()
    if (view === "controls") refreshHistory()
  }

  SystemClock { id: clock; precision: SystemClock.Minutes }
  PwObjectTracker { objects: [Pipewire.defaultAudioSink] }

  function showFeedback(message, duration, kind) {
    if (surfaceOpen) return
    if (feedbackKind === "notification" && kind !== "notification" && feedbackTimer.running) return
    feedback = String(message || "")
    feedbackKind = String(kind || "system")
    view = "feedback"
    feedbackTimer.interval = duration || 2800
    feedbackTimer.restart()
  }

  // ---------- Live activities ----------
  //
  // Short, pretty notes for things that just happened (in the same spirit as
  // "copied to clipboard"): connect, unplug, screenshot, theme. They all share
  // the feedback pill, and stay quiet for the first couple of seconds so a
  // status that is merely the startup state is not announced.
  property bool activityReady: false
  Timer { interval: 2500; running: true; onTriggered: root.activityReady = true }

  function announce(message) {
    if (!initialized || !activityReady || !message) return
    // A fullscreen window asked the pill to stay away; a status note is not
    // worth popping back in for.
    if (pillHidden) return
    showFeedback(message, 2200, "system")
  }

  // Wi-Fi: announce the network we landed on, and what we left.
  readonly property string connectedWifi: {
    var devices = Networking.devices ? Networking.devices.values : []
    for (var i = 0; i < devices.length; i++) {
      var d = devices[i]
      if (!d || d.type !== DeviceType.Wifi || !d.connected) continue
      var nets = d.networks ? d.networks.values : []
      for (var j = 0; j < nets.length; j++)
        if (nets[j] && nets[j].connected) return String(nets[j].name || "")
    }
    return ""
  }
  property string lastWifi: ""
  onConnectedWifiChanged: {
    var name = connectedWifi
    if (name === lastWifi) return
    var previous = lastWifi
    lastWifi = name
    if (name !== "") announce("Connected to " + name)
    else if (previous !== "") announce("Wi-Fi disconnected")
  }

  // Bluetooth: the device that just came or went.
  readonly property string connectedBluetooth: {
    var devices = Bluetooth.devices ? Bluetooth.devices.values : []
    for (var i = 0; i < devices.length; i++) {
      var d = devices[i]
      if (d && d.connected) return String(d.name || d.deviceName || "")
    }
    return ""
  }
  property string lastBluetooth: ""
  onConnectedBluetoothChanged: {
    var name = connectedBluetooth
    if (name === lastBluetooth) return
    lastBluetooth = name
    if (name !== "") announce(name + " connected")
  }

  // Power source: plugged in, unplugged, or full.
  Connections {
    target: UPower
    function onOnBatteryChanged() {
      if (UPower.onBattery) root.announce("On battery power")
      else root.announce(root.batteryFull ? "Battery full" : "Charging")
    }
  }

  // Screenshots: Omarchy drops them straight into the pictures folder.
  property string picturesDir: Quickshell.env("HOME") + "/Pictures"
  Process {
    running: true
    command: ["xdg-user-dir", "PICTURES"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var dir = String(text || "").trim()
        if (dir) root.picturesDir = dir
      }
    }
  }
  FolderListModel {
    id: screenshotWatch
    folder: "file://" + root.picturesDir
    nameFilters: ["screenshot-*.png"]
    showDirs: false
    onCountChanged: root.checkScreenshot()
  }
  // The model is not reliably sorted, so remember which files we have already
  // accounted for instead of trusting an index.
  property var knownScreenshots: ({})
  function checkScreenshot() {
    if (screenshotWatch.count === 0) return
    var fresh = ""
    for (var i = 0; i < screenshotWatch.count; i++) {
      var name = String(screenshotWatch.get(i, "fileName") || "")
      if (name === "" || knownScreenshots[name] === true) continue
      knownScreenshots[name] = true
      // Only genuinely fresh files: deleting one promotes an old file into the
      // model again, and that is not a new screenshot.
      var modified = screenshotWatch.get(i, "fileModified")
      var age = modified ? Date.now() - new Date(modified).getTime() : 0
      if (age >= 0 && age < 15000) fresh = name
    }
    if (fresh !== "") announce("Screenshot saved")
  }

  // ---------- Notification click ----------
  //
  // Clicking a notification opens whatever sent it: a notification carrying its
  // own action (Omarchy's installer toasts) runs that, otherwise the app's
  // window is focused, and failing that its desktop entry is launched.
  readonly property string openSourceScript:
    'app="$1"; [ -n "$app" ] || exit 1; ' +
    'pat=$(printf "%s" "$app" | sed "s/ /[ -]/g"); ' +
    'if [ "$pat" != "$app" ]; then omarchy-hyprland-focus-app "$pat" >/dev/null 2>&1 && exit 0; fi; ' +
    'omarchy-hyprland-focus-app "$app" >/dev/null 2>&1 && exit 0; ' +
    'for dir in "$HOME/.local/share/applications" /usr/share/applications; do ' +
      'for f in "$dir"/*.desktop; do ' +
        '[ -e "$f" ] || continue; ' +
        'name=$(grep -im1 "^Name=" "$f" | cut -d= -f2-); ' +
        '[ -n "$name" ] || continue; ' +
        'case "$app" in *"$name"*) exec gtk-launch "$(basename "$f" .desktop)";; esac; ' +
      'done; ' +
    'done; ' +
    'exit 1'
  Process { id: openSource }
  function activateNotification(row) {
    if (!row) return
    var argv = NotificationLogic.parseExecArgv(row.execArgv)
    if (argv) {
      Quickshell.execDetached(argv)
    } else {
      openSource.command = ["bash", "-c", openSourceScript, "--", String(row.app || row.summary || "")]
      openSource.running = true
    }
    if (row.isActive) notificationCommand("dismissKey", row)
  }

  onVolumeChanged: {
    if (initialized && volume >= 0 && settings.volumeHud) showFeedback("", 1800, "volume")
  }
  onMutedChanged: {
    if (initialized && volume >= 0 && settings.volumeHud) showFeedback("", 1800, "volume")
  }
  Component.onCompleted: {
    initialized = true
    companionCheck.running = true
  }

  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string companionDir: pluginDir + "/companion"
  property string companionStatus: ""
  property bool companionInstalling: false
  readonly property bool companionNeedsSetup: companionStatus !== "" && companionStatus !== "ok"
  readonly property string companionWarning: companionInstalling ? "Installing notifications…"
    : companionStatus === "missing" ? "Set up notifications"
    : companionStatus === "outdated" ? "Update notifications"
    : companionStatus === "not-enabled" ? "Enable notifications"
    : companionStatus === "menu" ? "Set up switchers"
    : "Notifications need setup"

  Process {
    id: companionCheck
    command: ["bash", root.companionDir + "/check.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.companionStatus = String(text || "").trim()
    }
  }

  function installCompanion() {
    if (companionInstall.running) return
    companionInstalling = true
    companionInstall.command = ["bash", companionDir + "/install.sh"]
    companionInstall.running = true
  }
  Process {
    id: companionInstall
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: if (text) console.warn("island: companion install:", text) }
    onExited: function(code) {
      root.companionInstalling = false
      companionCheck.running = true
    }
  }

  Timer {
    id: feedbackTimer
    repeat: false
    onTriggered: {
      if (root.view === "feedback") root.view = "rest"
      root.feedbackKind = ""
    }
  }

  Timer {
    id: surfaceRevealTimer
    interval: 90 * root.motionScale
    repeat: false
    onTriggered: root.surfaceContentReady = true
  }

  FileView {
    id: feedFile
    path: root.feedPath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadFeed(text())
    onFileChanged: reload()
  }

  function loadFeed(raw) {
    try {
      var parsed = JSON.parse(raw || "{}")
      var rows = Array.isArray(parsed.active) ? parsed.active : []
      activeNotifications = rows
      if (view === "controls") refreshHistory()
      if (!rows.length) return
      var current = rows[0]
      var key = String(current.timestamp) + ":" + String(current.originalId)
      if (key === lastNotificationKey) return
      lastNotificationKey = key
      lastNotification = current
      if (!surfaceOpen) showFeedback(String(current.summary || current.app || "Notification"), settings.bannerSeconds * 1000, "notification")
    } catch (e) {
      console.warn("island: notification feed parse failed", e)
    }
  }

  Process {
    id: historyProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadHistory(text)
    }
  }

  function refreshHistory() {
    if (historyProc.running) return
    historyProc.command = ["bash", "-c", "awk 1 \"$1\"/*.json 2>/dev/null || true", "--", historyDir]
    historyProc.running = true
  }

  function loadHistory(raw) {
    var rows = []
    for (var j = 0; j < activeNotifications.length; j++) {
      var active = Object.assign({}, activeNotifications[j])
      active.isActive = true
      rows.push(active)
    }
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].trim()) continue
      try { rows.push(JSON.parse(lines[i])) } catch (e) { }
    }
    rows.sort(function(a, b) { return Number(b.timestamp || 0) - Number(a.timestamp || 0) })
    history = rows.slice(0, 10)
  }

  function notificationKey(row) {
    return String(row.timestamp) + ":" + String(row.originalId)
  }

  function notificationCommand(method, row) {
    notificationProc.command = ["omarchy-shell", "notifications", method, notificationKey(row)]
    notificationProc.running = true
  }
  Process { id: notificationProc; running: false; onExited: root.refreshHistory() }

  function dismissPillNotification() {
    var row = lastNotification
    feedbackKind = ""
    view = "rest"
    if (row) notificationCommand("dismissKey", row)
  }

  function clearAllNotifications() {
    history = []
    notificationProc.command = ["bash", "-c", "omarchy-shell notifications dismissAll; omarchy-shell notifications clear"]
    notificationProc.running = true
  }

  function dismissNotification(row) {
    var key = notificationKey(row)
    history = history.filter(function(r) { return notificationKey(r) !== key })
    if (row.isActive) {
      notificationProc.command = ["omarchy-shell", "notifications", "dismissKey", key]
    } else {
      var stem = String(row.timestamp) + "-" + String(row.originalId)
      notificationProc.command = ["bash", "-c", "rm -f \"$1/$2.json\" \"$1/../images/$2\"-*", "--", historyDir, stem]
    }
    notificationProc.running = true
  }

  property string menuRoute: "root"

  function toggleView(name) {
    view = view === name ? "rest" : name
    return view
  }

  IpcHandler {
    target: "guilhermerisu.island"
    function show(name: string): string {
      if (name === "menu") root.menuRoute = "root"
      return root.toggleView(name)
    }
    function openMenu(route: string): string {
      root.menuRoute = String(route || "root")
      root.view = "menu"
      return root.view
    }
    function toggle(): string { return root.toggleView("controls") }
    function themes(): string { return root.toggleView("themes") }
    function wallpapers(): string { return root.toggleView("wallpapers") }
    function apps(): string { return root.toggleView("apps") }
    function power(): string { return root.toggleView("power") }
    function ask(question: string): string {
      root.ask(question)
      return root.view
    }
    function companionStatus(): string { return root.companionStatus }
    function installCompanion(): string {
      root.installCompanion()
      return "installing"
    }
    function showHistory(): string {
      root.view = "controls"
      return root.view
    }
    function close(): string {
      root.view = "rest"
      return "rest"
    }
  }

  Variants {
    model: Quickshell.screens
    delegate: Component {
      PanelWindow {
        id: window
        required property var modelData
        screen: modelData
        visible: modelData.name === root.outputName
        color: "transparent"
        surfaceFormat.opaque: false
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; left: true; right: true }
        implicitHeight: 800
        WlrLayershell.namespace: "omarchy-island"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: island.activeSurface && island.activeSurface.wantsKeyboard
          ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        mask: Region { item: island }
        // The frost comes from a Hyprland layer rule on this namespace (see
        // ~/.config/hypr/looknfeel.lua), not from BackgroundEffect: a protocol
        // blur region is a plain rectangle, which left a frosted border around
        // the rounded pill and covered the whole window while the pill was
        // slid off-screen.

        HyprlandFocusGrab {
          id: focusGrab
          windows: [window]
          property bool armed: false
          active: window.visible && root.surfaceOpen && armed
          onCleared: if (root.surfaceOpen) root.view = "rest"
        }
        Timer {
          interval: 120
          running: root.surfaceOpen
          onTriggered: focusGrab.armed = true
        }
        Connections {
          target: root
          function onSurfaceOpenChanged() { if (!root.surfaceOpen) focusGrab.armed = false }
        }

        Canvas {
          id: leftEar
          readonly property real r: 10
          visible: root.settings.notch
          x: island.x - r
          y: island.y
          width: r
          height: r
          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.fillStyle = root.colorBackground
            ctx.beginPath()
            ctx.moveTo(r, 0)
            ctx.lineTo(r, r)
            ctx.arc(0, r, r, 0, -Math.PI / 2, true)
            ctx.closePath()
            ctx.fill()
          }
        }
        Canvas {
          id: rightEar
          readonly property real r: 10
          visible: root.settings.notch
          x: island.x + island.width
          y: island.y
          width: r
          height: r
          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.fillStyle = root.colorBackground
            ctx.beginPath()
            ctx.moveTo(0, 0)
            ctx.lineTo(0, r)
            ctx.arc(r, r, r, Math.PI, 1.5 * Math.PI, false)
            ctx.closePath()
            ctx.fill()
          }
        }

        Rectangle {
          id: island
          x: (parent.width - width) / 2
          y: root.pillHidden ? -height - 12 : root.settings.notch ? 0 : 8
          Behavior on y { NumberAnimation { duration: 300 * root.motionScale; easing.type: Easing.OutCubic } }
          readonly property Item activeSurface: views.surfaceFor(root.view)
          readonly property real targetWidth: activeSurface ? activeSurface.islandWidth
            : root.notificationPill ? 440
            : root.volumePill ? 240
            : root.clipboardPill ? 320
            : root.view === "feedback" ? 330
            : root.companionNeedsSetup ? 250
            : root.downloadDone ? 360
            : root.downloadActive ? (root.downloadTracker.active ? 240 : 280)
            : root.mediaPill ? 240
            : root.restWidth
          readonly property real targetHeight: activeSurface ? activeSurface.islandHeight
            : root.notificationPill ? 84
            : root.clipboardPill ? (root.settings.notch ? 40 : 44)
            : root.downloadDone ? 64
            : root.mediaPill || root.downloadPill ? (root.settings.notch ? 40 : 44)
            : root.volumePill ? 56
            : root.view === "rest" ? (root.settings.notch ? 36 : 40) : 52
          property real radiusCap: root.volumePill ? 20 : root.view === "answer" ? 44 : root.surfaceOpen ? 30 : 38
          Behavior on radiusCap {
            NumberAnimation { duration: 390 * root.motionScale; easing.type: Easing.OutQuint }
          }
          radius: Math.min(height / 2, root.settings.notch && !root.surfaceOpen ? Math.min(radiusCap, 16) : radiusCap)
          topLeftRadius: root.settings.notch ? 0 : radius
          topRightRadius: root.settings.notch ? 0 : radius
          scale: root.view === "rest" && clockHover.hovered && root.settings.hoverLift && !root.settings.notch ? 1.07 : 1
          Behavior on scale { NumberAnimation { duration: 240 * root.motionScale; easing.type: Easing.OutBack; easing.overshoot: 1.8 } }
          HoverHandler { id: clockHover; enabled: root.view === "rest" }
          color: root.colorBackground
          clip: true
          // A plain eased resize rather than a spring: the spring overshoots and
          // keeps settling for hundreds of milliseconds after the motion has
          // visually finished, re-laying out the island on every one of those
          // frames. This reaches the target exactly, and stops.
          readonly property int morphDuration: Math.round(300 * root.motionScale)
          // The morph starts one frame after a view change: the incoming view
          // builds its scene graph and paints on the frame of the change, and
          // that frame is over budget on its own. Giving it its own frame keeps
          // the motion itself clean.
          property real morphTargetWidth: targetWidth
          property real morphTargetHeight: targetHeight
          onTargetWidthChanged: Qt.callLater(function() { island.morphTargetWidth = island.targetWidth })
          onTargetHeightChanged: Qt.callLater(function() { island.morphTargetHeight = island.targetHeight })
          property real morphWidth: morphTargetWidth
          property real morphHeight: morphTargetHeight
          Behavior on morphWidth {
            NumberAnimation { duration: island.morphDuration; easing.type: Easing.OutQuint }
          }
          Behavior on morphHeight {
            NumberAnimation { duration: island.morphDuration; easing.type: Easing.OutQuint }
          }
          width: Math.max(40, Math.round(morphWidth))
          height: Math.max(28, Math.round(morphHeight))
          Behavior on color { ColorAnimation { duration: 240 * root.motionScale; easing.type: Easing.InOutQuad } }

          MouseArea {
            anchors.fill: parent
            enabled: root.view === "rest" || root.view === "feedback"
            onClicked: function(mouse) {
              feedbackTimer.stop()
              if (root.notificationPill) root.activateNotification(root.lastNotification)
              else if (root.clipboardPill) root.view = "clipboard"
              else if (root.view === "rest" && root.companionNeedsSetup) root.installCompanion()
              else if (root.downloadDone || (root.downloadActive && (mouse.x < 56 || mouse.x > width - 90))) root.openDownloads()
              else if (root.mediaPill && (mouse.x < 56 || mouse.x > width - 72)) root.view = "player"
              else root.view = "controls"
            }
          }

          NotificationPill { host: root; shape: island; anchors.fill: parent }

          VolumeSlider { host: root; shape: island; anchors.fill: parent }

          ClipboardPill { host: root; anchors.fill: parent }

          MediaPill { host: root; anchors.fill: parent }

          DownloadPill { host: root; anchors.fill: parent }

          IslandLabel { host: root; anchors.centerIn: parent }

          Views {
            id: views
            host: root
            // Sized to the island's destination, not to its animating size: the
            // view tree then lays out once per view change instead of on every
            // frame of the morph. The island clips it while it is still growing
            // (the content is hidden until the morph is nearly done anyway).
            width: island.targetWidth
            height: island.targetHeight
            x: Math.round((island.width - width) / 2)
            y: 0
          }

          WorkspaceDots {
            id: workspaceDots
            host: root
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.accessoriesShown ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 150 * root.motionScale; easing.type: Easing.InOutQuad } }
          }

          BatteryBadge {
            id: batteryBadge
            host: root
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.accessoriesShown && root.batteryPresent ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 150 * root.motionScale; easing.type: Easing.InOutQuad } }
          }
        }
      }
    }
  }
}
