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
import "views/shelf/ShelfModel.js" as ShelfModel
import "file:///usr/share/omarchy/shell/plugins/clipboard/ClipboardHistory.js" as ClipboardHistory
import "companion/lanta.notifications/NotificationLogic.js" as NotificationLogic

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
  readonly property bool mediaPill: view === "rest" && mediaPlaying && !companionNeedsSetup && settings.mediaPill && !downloadPill && !systemPill && !timerPill

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
  // Live CPU/memory/temperature, shared by the monitor live activity and its
  // page. It only takes the pill when pinned, or on its own when the machine
  // is running hot.
  SystemStats {
    id: systemSampler
    active: root.view === "system" || root.settings.systemMonitor || root.settings.autoMonitorHot
  }
  readonly property var systemStats: systemSampler
  readonly property bool systemPinned: !!settings.systemMonitor
  readonly property bool systemHot: !!settings.autoMonitorHot && systemSampler.ready && (systemSampler.temp >= 85 || systemSampler.cpu >= 95)
  readonly property bool systemPill: view === "rest" && !companionNeedsSetup && systemSampler.ready && !timerPill
    && (systemPinned || systemHot)
  // Countdown timer, shared by the control-center chip, the Timer page, and
  // the live activity on the resting pill.
  TimerService { id: timerService }
  readonly property var timer: timerService
  readonly property bool timerRunning: timerService.running
  readonly property bool timerPill: view === "rest" && !companionNeedsSetup && timerService.running
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
      property int nightTemp: 4000
      property bool notch: false
      property bool solidBlack: false
      property bool keepShelf: false
      property bool downloads: true
      property bool clipboard: true
      property bool systemUpdates: true
      property bool systemMonitor: false
      property bool pomodoro: false
      property bool hideFullscreen: true
      property string askAi: "chatgpt"
      property bool clockSeconds: false
      property bool workspaceDots: true
      property bool batteryBadge: true
      property bool timerChime: true
      property bool timerNotify: true
      property bool autoMonitorHot: true
    }
  }
  readonly property string feedPath: home + "/.local/state/omarchy/island-feed.json"
  readonly property string historyDir: home + "/.local/state/omarchy/notifications/history/"
  property string themeName: ""

  readonly property var clockDate: clock.date
  property string view: "rest"
  // Back navigation: `view` is a flat string, so remember where each screen
  // was opened from. Esc walks that history back a step and never closes the
  // island -- the Win/Super key does that.
  property var viewHistory: []
  property string viewBeforeChange: "rest"
  property bool restoringView: false
  readonly property bool notificationPill: view === "feedback" && feedbackKind === "notification"
  readonly property bool volumePill: view === "feedback" && feedbackKind === "volume"
  readonly property bool brightnessPill: view === "feedback" && feedbackKind === "brightness"
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

  // ---------- Shelf ----------
  //
  // Files, images, links and text parked on the island. Memory-only on purpose:
  // a shell restart (or reboot) empties it, and nothing is written to disk.
  property var shelf: []
  readonly property int shelfCount: shelf.length
  // True while a file/link/text is being dragged over the island, so the pill
  // can show a drop ring.
  property bool dropActive: false
  // True while a shelf tile is being dragged out, so the island stops claiming
  // the whole band and lets the drop reach the app underneath.
  property bool tileDragging: false
  // Hovering a drag over the resting pill for a moment opens the shelf, so a
  // small target turns into a big one before the drop.
  onDropActiveChanged: {
    if (dropActive && view === "rest") dropReveal.restart()
    else if (!dropActive) dropReveal.stop()
  }
  Timer {
    id: dropReveal
    interval: 500
    onTriggered: if (root.dropActive && root.view === "rest") root.view = "shelf"
  }

  function shelfAdd(entry) {
    var next = ShelfModel.add(shelf, entry)
    var grew = next.length > shelf.length
    shelf = next
    if (grew) announce("Added to shelf")
    return grew
  }
  function shelfRemove(item) {
    if (!item) return
    shelf = ShelfModel.removeKey(shelf, ShelfModel.itemKey(item))
  }
  function shelfClear() { shelf = [] }

  // ---------- Shelf persistence ----------
  //
  // The shelf is memory-only by default, so a restart empties it. With the
  // "Keep Shelf" setting on it is mirrored to a small JSON file and restored
  // on the next launch.
  property bool shelfRestoring: false
  readonly property string shelfPath: home + "/.local/state/omarchy/island-shelf.json"
  function parseShelf(raw) {
    try {
      var data = JSON.parse(String(raw || "[]"))
      if (!Array.isArray(data)) return []
      var out = []
      for (var i = 0; i < data.length; i++) {
        var item = ShelfModel.normalize(data[i])
        if (item) out.push(item)
      }
      return out
    } catch (e) {
      return []
    }
  }
  function saveShelf() {
    shelfFile.setText(JSON.stringify(root.shelf, null, 2) + "\n")
  }
  onShelfChanged: {
    if (!root.shelfRestoring && root.settings.keepShelf) root.saveShelf()
  }
  Connections {
    target: root.settings
    function onKeepShelfChanged() { if (root.settings.keepShelf) root.saveShelf() }
  }
  FileView {
    id: shelfFile
    path: root.shelfPath
    atomicWrites: true
    printErrors: false
    onLoaded: {
      // An in-memory shelf (a plugin reload, not a fresh start) wins.
      if (root.shelf.length > 0) return
      root.shelfRestoring = true
      root.shelf = root.parseShelf(text())
      root.shelfRestoring = false
    }
    onLoadFailed: function(error) { if (error !== FileViewError.FileNotFound) return }
  }
  function shelfAddText(raw) {
    var items = ShelfModel.fromText(raw)
    if (!items.length) return
    var next = shelf
    for (var i = 0; i < items.length; i++) next = ShelfModel.add(next, items[i])
    if (next.length === shelf.length) return
    shelf = next
    announce("Added to shelf")
  }
  Process {
    id: shelfPaste
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.shelfAddText(String(text || ""))
    }
  }
  // Park the current clipboard (a file uri-list when the app offers one,
  // otherwise text) for the `shelfAdd` keybind.
  function shelfAddClipboard() {
    if (shelfPaste.running) return
    shelfPaste.command = ["bash", "-c",
      'if wl-paste --list-types 2>/dev/null | grep -qx "text/uri-list"; then '
      + 'wl-paste --type text/uri-list --no-newline 2>/dev/null; '
      + 'else wl-paste --type text --no-newline 2>/dev/null; fi']
    shelfPaste.running = true
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

  // Frosted glass: the theme background at partial alpha. The "Solid Black"
  // option drops the glass for an opaque black pill with white ink, the way
  // the original Island looked.
  readonly property color colorBackground: settings.solidBlack ? "#000000" : withAlpha(Color.background, 0.72)
  readonly property color colorText: settings.solidBlack ? "#ffffff" : Color.foreground
  // A dimmed foreground rather than the theme's `muted`: the pill now sits on
  // the theme's own background at partial alpha, and themes whose muted is a
  // near-background colour (kanagawa: #54546D) become unreadable there.
  readonly property color colorMuted: withAlpha(colorText, 0.62)
  readonly property color colorAccent: settings.solidBlack
    ? "#ffffff"
    : luminance(Color.background) < 0.5 ? "#ffffff" : "#14141a"
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

  // ---------- Motion ----------
  // The island's whole animation vocabulary lives here. No view or component
  // invents its own timing: each one picks the duration and easing that match
  // its job, so everything moves at one tempo and one easing family.
  //
  //   instant - feedback under the pointer: press, hover, a slider filling
  //   base    - a state change: colour, switch, icon, chip
  //   panel   - the pill reshaping, a card opening, a progress bar filling
  //   open    - the pill growing out of the resting state
  //   fadeIn  - content arriving; fadeOut is much quicker, so a swap reads as
  //             one page replacing another instead of two showing through
  readonly property int motionInstant: Math.round(120 * motionScale)
  readonly property int motionBase: Math.round(180 * motionScale)
  readonly property int motionPanel: Math.round(240 * motionScale)
  readonly property int motionOpen: Math.round(300 * motionScale)
  readonly property int motionDelay: Math.round(110 * motionScale)
  readonly property int motionFadeIn: Math.round(150 * motionScale)
  readonly property int motionFadeOut: Math.round(70 * motionScale)

  // One easing per role, never per feel. Anything that moves or fades in uses
  // easeStandard; the pill opening leans on easeEmphasis so it leaves quickly
  // and settles; easeCross is for one thing replacing another; easePop carries
  // the small overshoot on badges.
  readonly property int easeStandard: Easing.OutCubic
  readonly property int easeEmphasis: Easing.OutQuint
  readonly property int easeCross: Easing.InOutQuad
  readonly property int easePop: Easing.OutBack

  // Small status accessories (workspace dots, battery) sit beside the clock
  // only in the plain resting state, so they never crowd a live activity.
  readonly property bool accessoriesShown: view === "rest" && !mediaPill && !downloadPill && !systemPill && !timerPill && !companionNeedsSetup
  // Room reserved for the clock text so the accessories never crowd it.
  readonly property real clockSlot: settings.clockSeconds ? 86 : 56
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
  // Accessories can be switched off, so the resting pill shrinks to match.
  readonly property bool workspaceDotsShown: !!settings.workspaceDots && workspaceIds.length > 0
  readonly property bool batteryBadgeShown: !!settings.batteryBadge && batteryPresent
  readonly property real restWidth: {
    if (!accessoriesShown) return 100
    var width = 24 + clockSlot
    if (workspaceDotsShown) width += workspaceDotsWidth + 10
    if (batteryBadgeShown) width += batteryBadgeWidth + 10
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
    if (restoringView) {
      restoringView = false
    } else if (view === "rest") {
      viewHistory = []
    } else if (view !== viewBeforeChange && viewBeforeChange !== "feedback") {
      // Remember every screen we passed through, the pill included, so Esc can
      // retrace the path and the topmost screen lands back on the pill.
      viewHistory = viewHistory.concat([viewBeforeChange])
    }
    viewBeforeChange = view
    surfaceContentReady = false
    if (surfaceOpenFor(view)) surfaceRevealTimer.restart()
    else surfaceRevealTimer.stop()
    if (view === "controls") refreshHistory()
  }

  SystemClock {
    id: clock
    precision: root.settings.clockSeconds ? SystemClock.Seconds : SystemClock.Minutes
  }
  // The source is tracked too so its level meter has something to report.
  PwObjectTracker { objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource] }

  // One weather service for the whole island: the control center's chip and the
  // Weather page share this, so a location is fetched and cached once.
  readonly property var weather: weatherService
  Weather { id: weatherService; host: root }

  // The notification companion's setup state, and installing it.
  readonly property var companion: companionService
  Companion { id: companionService; host: root }
  readonly property string companionStatus: companion.status
  readonly property bool companionInstalling: companion.installing
  readonly property bool companionNeedsSetup: companion.needsSetup
  readonly property string companionWarning: companion.warning
  function installCompanion() { companion.install() }

  // The control center's small status reads, kept out of the panel.
  readonly property var omarchyStatus: omarchyStatusService
  OmarchyStatus { id: omarchyStatusService; host: root }

  // The control center's controls (power profiles, brightness, Game Mode).
  readonly property var omarchyControls: omarchyControlsService
  OmarchyControls { id: omarchyControlsService; host: root }

  // ---------- Optional Omarchy helpers ----------
  //
  // Island leans on a pile of omarchy-* scripts. On an older Omarchy release,
  // or a trimmed install, some of them are simply not there -- and a missing
  // helper used to mean a chip that never fills in, or a button that looks
  // perfectly normal and does nothing at all. The whole list is probed once at
  // startup (on PATH and in Omarchy's own bin directory); a feature whose helper
  // is missing hides itself, or says why, instead of failing quietly.
  property var helpers: ({})
  property bool helpersProbed: false
  readonly property bool helpersReady: helpersProbed
  function hasHelper(name) { return helpers[name] === true }

  readonly property var helperNames: [
    "omarchy-bluetooth-device",
    "omarchy-brightness-display",
    "omarchy-capture-screenrecording",
    "omarchy-clipboard-open",
    "omarchy-clipboard-paste-file",
    "omarchy-clipboard-paste-text",
    "omarchy-hibernation-available",
    "omarchy-launch-floating-terminal-with-presentation",
    "omarchy-menu",
    "omarchy-notification-send",
    "omarchy-powerprofiles-list",
    "omarchy-powerprofiles-set",
    "omarchy-reminder",
    "omarchy-system-lock",
    "omarchy-system-reboot",
    "omarchy-system-shutdown",
    "omarchy-theme-bg-set",
    "omarchy-theme-set",
    "omarchy-toggle-enabled",
    "omarchy-update",
    "omarchy-update-available",
    "omarchy-voxtype-status",
    "notify-send"
  ]

  Process {
    id: helperProbe
    running: true
    command: ["bash", "-c",
      'bin=$1; shift; for c in "$@"; do ' +
      'if command -v "$c" >/dev/null 2>&1 || { [ -n "$bin" ] && [ -x "$bin/$c" ]; }; then printf "%s\n" "$c"; fi; ' +
      'done', "--", root.omarchyPath !== "" ? root.omarchyPath + "/bin" : ""].concat(root.helperNames)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var found = {}
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var name = lines[i].trim()
          if (name !== "") found[name] = true
        }
        root.helpers = found
        root.helpersProbed = true
      }
    }
  }

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

  // A finished timer says so, chimes, and (in Pomodoro mode) starts the other
  // half of the cycle.
  Process { id: timerChime }
  Process { id: timerNotify }
  Connections {
    target: timerService
    function onDone(label) {
      root.announce(label + " finished")
      if (root.settings.timerChime) {
        timerChime.command = ["pw-play", root.pluginDir + "/assets/chime.wav"]
        timerChime.running = true
      }
      if (root.settings.timerNotify) {
        // The Omarchy helper routes through the companion and gets the island's
        // own styling; notify-send is what a machine without it can still do.
        timerNotify.command = root.hasHelper("omarchy-notification-send")
          ? ["omarchy-notification-send", "Timer", label + " finished"]
          : ["notify-send", "Timer", label + " finished"]
        timerNotify.running = true
      }
      if (root.settings.pomodoro)
        timerService.start(label === "Focus" ? 5 * 60 : 25 * 60, label === "Focus" ? "Break" : "Focus")
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
  // Clicking a notification opens what it is about. Omarchy's own installer
  // toasts carry the action as an argv vector and run that. Everyone else
  // registers the jump under the libnotify "default" action — for Telegram it
  // is what switches to the exact chat. A row that is still live has that
  // action, so the notification service invokes it; a history row has no action
  // left (the sender destroyed it), so falling back to the app's window, and
  // then to its desktop entry, is all that is possible.
  readonly property string openSourceScript:
    'app="$1"; [ -n "$app" ] || exit 1; ' +
    'pat=$(printf "%s" "$app" | sed "s/ /[ ._-]/g"); ' +
    'if [ "$pat" != "$app" ]; then omarchy-hyprland-focus-app "$pat" >/dev/null 2>&1 && exit 0; fi; ' +
    'omarchy-hyprland-focus-app "$app" >/dev/null 2>&1 && exit 0; ' +
    'for dir in "$HOME/.local/share/applications" /usr/share/applications; do ' +
      'for f in "$dir"/*.desktop; do ' +
        '[ -e "$f" ] || continue; ' +
        'name=$(grep -im1 "^Name=" "$f" | cut -d= -f2-); ' +
        '[ -n "$name" ] || continue; ' +
        // gtk-launch wants the desktop-file basename: an id that already ends
        // in .desktop (org.telegram.desktop.desktop) is used verbatim, so
        // stripping the suffix here would look for a file that does not exist.
        'case "$app" in *"$name"*) exec gtk-launch "$(basename "$f")";; esac; ' +
      'done; ' +
    'done; ' +
    'exit 1'
  Process { id: openSource }
  function activateNotification(row) {
    if (!row) return
    var argv = NotificationLogic.parseExecArgv(row.execArgv)
    if (argv) {
      Quickshell.execDetached(argv)
      if (row.isActive) notificationCommand("dismissKey", row)
      return
    }
    // The sender's libnotify "default" action is what opens the specific thing
    // the notification is about — Telegram switches to the exact chat — and only
    // a live row still owns it. The service invokes it, then dismisses the toast;
    // if the sender registered no action it focuses the app window instead.
    if (row.isActive) notificationCommand("invokeKey", row)
    // Raise or launch the app as well: on Wayland the sender's own activation
    // request is not guaranteed to focus its window, and a history row has no
    // live action left, so this is the only route it has.
    openSource.command = ["bash", "-c", openSourceScript, "--", String(row.app || row.summary || "")]
    openSource.running = true
  }

  onVolumeChanged: {
    if (initialized && volume >= 0 && settings.volumeHud) showFeedback("", 1800, "volume")
  }
  onMutedChanged: {
    if (initialized && volume >= 0 && settings.volumeHud) showFeedback("", 1800, "volume")
  }

  // Brightness HUD. The brightness keys run `omarchy-brightness-display` and
  // then ping the island, which reads the value back here: sysfs backlight
  // attributes don't emit inotify, so a file watch would never fire.
  property real brightnessLevel: 0
  Process {
    id: brightnessProbe
    command: ["omarchy-brightness-display", "--monitor", root.outputName]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var value = parseInt(String(text || "").trim(), 10)
        if (isNaN(value)) return
        root.brightnessLevel = Math.max(0, Math.min(1, value / 100))
        root.showFeedback("", 1800, "brightness")
      }
    }
  }

  Component.onCompleted: {
    initialized = true
  }

  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
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
      // The banner row is live by definition — the feed's active list is what
      // popupModel is showing — and activateNotification relies on this flag to
      // invoke the sender's action instead of only focusing its window.
      current.isActive = true
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

  // Esc: step back one screen. The pill is on the history too, so the topmost
  // screen lands back on it; the Win/Super key still closes from anywhere.
  function goBack(): string {
    if (view === "rest") return view
    if (viewHistory.length > 0) {
      var target = viewHistory[viewHistory.length - 1]
      viewHistory = viewHistory.slice(0, viewHistory.length - 1)
      restoringView = true
      view = target
      return view
    }
    // No history (a view opened before any transition): fall back to the pill.
    restoringView = true
    view = "rest"
    return view
  }

  IpcHandler {
    target: "lanta.island"
    function show(name: string): string {
      if (name === "menu") root.menuRoute = "root"
      return root.toggleView(name)
    }
    function openMenu(route: string): string {
      root.menuRoute = String(route || "root")
      root.view = "menu"
      return root.view
    }
    function toggle(): string { root.view = root.view === "rest" ? "controls" : "rest"; return root.view }
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
    // Called by the touchpad keys (see the user's bindings.lua), which pass
    // the state they left the device in.
    function inputDevice(message: string): string {
      root.showFeedback(message, 1500, "system")
      return "ok"
    }
    // Called by the brightness keys (see the user's bindings.lua) after
    // omarchy-brightness-display has moved the backlight.
    function brightness(): string {
      if (!brightnessProbe.running) brightnessProbe.running = true
      return "ok"
    }
    // Start a countdown from a keybind or a script: `omarchy-shell
    // lanta.island timer 1500 Focus`.
    function timer(seconds: int, label: string): string {
      root.timer.start(seconds, label)
      return "ok"
    }
    function timerStop(): string {
      root.timer.stop()
      return "ok"
    }
    // The shelf: `omarchy-shell lanta.island shelf` toggles it, `shelfAdd`
    // parks the current clipboard, `shelfClear` empties it.
    function shelf(): string { return root.toggleView("shelf") }
    function shelfAdd(): string { root.shelfAddClipboard(); return "ok" }
    function shelfClear(): string { root.shelfClear(); return "ok" }
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
        WlrLayershell.keyboardFocus: island.activeSurface && island.activeSurface.wantsKeyboard && !root.tileDragging
          ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        // While a view is open the whole window takes input, so a click
        // anywhere outside the pill lands on the dismiss layer below and
        // closes it. The rest of the time only the pill itself is interactive,
        // which is what keeps the band from swallowing clicks aimed at the
        // windows underneath. A drag out of the shelf shrinks the region back
        // to the island, otherwise this overlay would swallow the drop before
        // it reached the app underneath.
        mask: Region { item: root.surfaceOpen && !root.tileDragging ? dismissArea : island }
        // The frost comes from a Hyprland layer rule on this namespace (see
        // ~/.config/hypr/looknfeel.lua), not from BackgroundEffect: a protocol
        // blur region is a plain rectangle, which left a frosted border around
        // the rounded pill and covered the whole window while the pill was
        // slid off-screen.

        HyprlandFocusGrab {
          id: focusGrab
          windows: [window]
          property bool armed: false
          // A keyboard grab gets in the way of dragging a tile out, so it steps
          // aside while a shelf tile is held.
          active: window.visible && root.surfaceOpen && armed && !root.tileDragging
          onCleared: if (root.surfaceOpen && !root.tileDragging) root.view = "rest"
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

        // Everything that is not the pill. Declared before it, so the pill's own
        // handlers stay on top; only reachable while a view is open (the mask
        // above is what limits input the rest of the time).
        MouseArea {
          id: dismissArea
          anchors.fill: parent
          enabled: root.surfaceOpen
          onClicked: root.view = "rest"
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
          Behavior on y { NumberAnimation { duration: root.motionOpen; easing.type: root.easeStandard } }
          readonly property Item activeSurface: views.surfaceFor(root.view)
          readonly property real targetWidth: activeSurface ? activeSurface.islandWidth
            : root.notificationPill ? 440
            : root.volumePill ? 240
            : root.brightnessPill ? 240
            : root.clipboardPill ? 320
            : root.view === "feedback" ? 330
            : root.companionNeedsSetup ? 250
            : root.downloadDone ? 360
            : root.downloadActive ? (root.downloadTracker.active ? 240 : 280)
            : root.timerPill ? 240
            : root.systemPill ? 240
            : root.mediaPill ? 240
            : root.dropActive ? 360
            : root.restWidth
          readonly property real targetHeight: activeSurface ? activeSurface.islandHeight
            : root.notificationPill ? 84
            : root.clipboardPill ? (root.settings.notch ? 40 : 44)
            : root.downloadDone ? 64
            : root.mediaPill || root.downloadPill || root.systemPill || root.timerPill ? (root.settings.notch ? 40 : 44)
            : root.volumePill ? 56
            : root.brightnessPill ? 56
            : root.dropActive ? 64
            : root.view === "rest" ? (root.settings.notch ? 36 : 40) : 52
          property real radiusCap: root.volumePill || root.brightnessPill ? 20 : root.view === "answer" ? 44 : root.surfaceOpen ? 30 : 38
          Behavior on radiusCap {
            NumberAnimation { duration: root.motionOpen; easing.type: root.easeEmphasis }
          }
          radius: Math.min(height / 2, root.settings.notch && !root.surfaceOpen ? Math.min(radiusCap, 16) : radiusCap)
          topLeftRadius: root.settings.notch ? 0 : radius
          topRightRadius: root.settings.notch ? 0 : radius
          scale: root.view === "rest" && clockHover.hovered && root.settings.hoverLift && !root.settings.notch ? 1.07 : 1
          Behavior on scale { NumberAnimation { duration: root.motionPanel; easing.type: root.easePop; easing.overshoot: 1.8 } }
          HoverHandler { id: clockHover; enabled: root.view === "rest" }
          color: root.colorBackground
          clip: true
          // A plain eased resize rather than a spring: the spring overshoots and
          // keeps settling for hundreds of milliseconds after the motion has
          // visually finished, re-laying out the island on every one of those
          // frames. This reaches the target exactly, and stops.
          readonly property int morphDuration: root.motionOpen
          // Collapsing is a two-stage move: the outgoing view fades first, so
          // the shell can then shrink on its own. That stage is shorter than the
          // opening one, because it no longer has to hide the content swap too.
          readonly property int collapseDuration: root.motionPanel
          readonly property int collapseDelay: root.motionDelay
          // Where the pill is heading, and which way. Opening starts on the next
          // frame (the incoming view builds and paints on the frame of the
          // change, and that frame is over budget on its own); closing waits for
          // the outgoing view to fade, so the content is gone before the pill
          // starts collapsing instead of being wiped away by the shrinking edge
          // while it is still fading.
          property real morphTargetWidth: targetWidth
          property real morphTargetHeight: targetHeight
          property bool expanding: true

          // True once the size animations have reached their destination. The
          // status accessories wait for it, so they fade in against a settled
          // pill rather than flying in from the edges of a collapsing one.
          readonly property bool settled: Math.abs(morphWidth - targetWidth) < 1.5
            && Math.abs(morphHeight - targetHeight) < 1.5
          readonly property bool accessoriesVisible: root.accessoriesShown && settled && !root.dropActive

          function syncMorphTarget() {
            island.morphTargetWidth = island.targetWidth
            island.morphTargetHeight = island.targetHeight
          }
          function scheduleMorph() {
            island.expanding = island.targetWidth >= island.morphWidth
            // Closing to the rest pill is staged (the outgoing view fades
            // first). A move between two open views is not: there the pill
            // should just take its new shape, with the views cross-fading.
            if (island.expanding || root.view !== "rest") {
              // The change that starts a view change moves the pill at once.
              // Anything arriving while it is still moving - a network list
              // streaming results in one row at a time, a scan filling in - is
              // coalesced instead: re-targeting a running animation on every
              // row is what made opening Wi-Fi look like a stutter. The pill
              // then makes one more smooth move to wherever the content
              // settled.
              if (!island.moving) {
                island.moving = true
                Qt.callLater(island.syncMorphTarget)
              }
              morphSettle.restart()
            } else {
              island.moving = false
              morphDelay.interval = island.collapseDelay
              morphDelay.restart()
            }
          }
          onTargetWidthChanged: island.scheduleMorph()
          onTargetHeightChanged: island.scheduleMorph()
          Timer { id: morphDelay; onTriggered: island.syncMorphTarget() }

          // Set while the pill is heading somewhere; cleared once the content
          // has held still for a moment.
          property bool moving: false
          Timer {
            id: morphSettle
            interval: 120
            onTriggered: {
              island.moving = false
              if (Math.abs(island.morphTargetWidth - island.targetWidth) > 1.5
                  || Math.abs(island.morphTargetHeight - island.targetHeight) > 1.5) {
                island.syncMorphTarget()
                island.moving = true
                morphSettle.restart()
              }
            }
          }

          property real morphWidth: morphTargetWidth
          property real morphHeight: morphTargetHeight
          Behavior on morphWidth {
            NumberAnimation {
              duration: island.expanding ? island.morphDuration : island.collapseDuration
              // OutQuint snaps and settles, which reads as a twitch on the way
              // down; the collapse gets a gentler curve.
              easing.type: island.expanding ? root.easeEmphasis : root.easeStandard
            }
          }
          Behavior on morphHeight {
            NumberAnimation {
              duration: island.expanding ? island.morphDuration : island.collapseDuration
              easing.type: island.expanding ? root.easeEmphasis : root.easeStandard
            }
          }
          width: Math.max(40, Math.round(morphWidth))
          height: Math.max(28, Math.round(morphHeight))
          Behavior on color { ColorAnimation { duration: root.motionPanel; easing.type: root.easeCross } }

          MouseArea {
            anchors.fill: parent
            // Always on, so a click on the pill is consumed here rather than
            // reaching the dismiss layer underneath and closing the view. It
            // only *acts* on the resting pill and the feedback pill; the views
            // declare their own handlers on top.
            onClicked: function(mouse) {
              if (root.view !== "rest" && root.view !== "feedback") return
              feedbackTimer.stop()
              if (root.notificationPill) {
                root.activateNotification(root.lastNotification)
                // The click opened what the notification was about; the banner
                // is spent. The stopped timer can no longer close it, so put the
                // island back to rest explicitly.
                root.feedbackKind = ""
                root.view = "rest"
              }
              else if (root.clipboardPill) root.view = "clipboard"
              else if (root.view === "rest" && root.companionNeedsSetup) root.installCompanion()
              else if (root.downloadDone || (root.downloadActive && (mouse.x < 56 || mouse.x > width - 90))) root.openDownloads()
              else if (root.timerPill) root.view = "timer"
              else if (root.systemPill) root.view = "system"
              else if (root.mediaPill && (mouse.x < 56 || mouse.x > width - 72)) root.view = "player"
              else if (root.view === "rest" && Math.abs(mouse.x - width / 2) <= root.clockSlot / 2 + 6) root.view = "calendar"
              else root.view = "controls"
            }
          }

          NotificationPill { host: root; shape: island; anchors.fill: parent }

          VolumeSlider { host: root; shape: island; anchors.fill: parent }

          BrightnessSlider { host: root; shape: island; anchors.fill: parent }

          ClipboardPill { host: root; anchors.fill: parent }

          MediaPill { host: root; anchors.fill: parent }

          SystemPill { host: root; anchors.fill: parent }

          TimerPill { host: root; anchors.fill: parent }

          DownloadPill { host: root; anchors.fill: parent }

          IslandLabel { host: root; anchors.centerIn: parent }

          // The view tree is sized to the *surface* it belongs to and not to the
          // island's animating (or destination) size. Two reasons: the tree then
          // lays out once per view change instead of on every frame of the
          // morph, and during a close it keeps the content still while it fades
          // -- deriving the position from the destination width made the whole
          // panel jump sideways by ~176px as the island closed.
          readonly property Item contentSurface: views.surfaceFor(root.view)
          property real lastContentWidth: 540
          property real lastContentHeight: 620
          onContentSurfaceChanged: {
            if (!contentSurface) return
            island.lastContentWidth = contentSurface.islandWidth
            island.lastContentHeight = contentSurface.islandHeight
          }
          readonly property real contentWidth: contentSurface ? contentSurface.islandWidth : lastContentWidth
          readonly property real contentHeight: contentSurface ? contentSurface.islandHeight : lastContentHeight

          Views {
            id: views
            host: root
            width: island.contentWidth
            height: island.contentHeight
            x: Math.round((island.width - width) / 2)
            y: 0
          }

          WorkspaceDots {
            id: workspaceDots
            host: root
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            opacity: island.accessoriesVisible && root.workspaceDotsShown ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: root.motionFadeIn; easing.type: root.easeCross } }
          }

          BatteryBadge {
            id: batteryBadge
            host: root
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            opacity: island.accessoriesVisible && root.batteryBadgeShown ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: root.motionFadeIn; easing.type: root.easeCross } }
          }

          // Drop files, links or text dragged from another app straight onto
          // the island and they land on the shelf. The target is whatever the
          // island currently shows: the rest pill (small, but it works), or the
          // open shelf, which is a far easier target. Accept on anything the
          // compositor offers and decide what it is on drop -- Wayland only
          // exposes the mime types up front, and some sources do not report
          // urls until the payload is read.
          DropArea {
            id: shelfDrop
            anchors.fill: parent
            onEntered: function(drag) {
              root.dropActive = true
            }
            onExited: function() {
              root.dropActive = false
            }
            onDropped: function(drop) {
              root.dropActive = false
              drop.accept(Qt.CopyAction)
              if (drop.hasUrls && drop.urls.length > 0) {
                var lines = []
                for (var i = 0; i < drop.urls.length; i++) lines.push(String(drop.urls[i]))
                root.shelfAddText(lines.join("\n"))
              } else if (drop.hasText) {
                root.shelfAddText(String(drop.text))
              }
              // Show the result, so a drop onto the rest pill opens the shelf
              // with the new items in it.
              root.view = "shelf"
            }
          }

          // Drop feedback: a soft accent wash, a matching outline, and -- while
          // the island is at rest -- a short hint in place of the clock, so the
          // target reads as a drop zone instead of a stretched pill.
          Rectangle {
            id: dropWash
            anchors.fill: parent
            radius: island.radius
            topLeftRadius: island.topLeftRadius
            topRightRadius: island.topRightRadius
            color: root.dropActive && !root.surfaceOpen ? root.withAlpha(root.colorAccent, 0.12) : "transparent"
            border.width: 2
            border.color: root.colorAccent
            opacity: root.dropActive ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: root.motionInstant; easing.type: root.easeStandard } }
          }
          Row {
            anchors.centerIn: parent
            spacing: 9
            opacity: root.dropActive && !root.surfaceOpen ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: root.motionInstant; easing.type: root.easeStandard } }
            Item {
              width: dropGlyph.implicitWidth
              height: 24
              Text {
                id: dropGlyph
                anchors.centerIn: parent
                text: "󰉋"
                color: root.colorAccent
                font.family: root.fontFamily
                font.pixelSize: 20
              }
            }
            Item {
              width: dropText.implicitWidth
              height: 24
              Text {
                id: dropText
                anchors.centerIn: parent
                text: "Drop to shelf"
                color: root.colorText
                font.family: "Adwaita Sans"
                font.pixelSize: 14
                font.weight: Font.DemiBold
              }
            }
          }
        }
      }
    }
  }
}
