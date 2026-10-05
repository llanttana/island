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
  // A history row is its own surface, not the card's 7% tint: the theme
  // background nudged 10% towards the text and then laid down almost opaque.
  // At 0.07 the row let the window behind it decide the text contrast -- a
  // white window washed it out -- where this keeps the same contrast whatever
  // is behind the panel and however the user's blur is set. The card around
  // it stays translucent.
  readonly property color noteRow: {
    var bg = host.colorBackground
    var fg = host.colorText
    return Qt.rgba(bg.r + (fg.r - bg.r) * 0.1,
                   bg.g + (fg.g - bg.g) * 0.1,
                   bg.b + (fg.b - bg.b) * 0.1,
                   0.92)
  }
  // Hairline that defines a card against the frosted glass behind it.
  readonly property color border: host.colorBorder
  readonly property string iconFont: host.fontFamily
  readonly property int animDuration: host.motionBase

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
  readonly property var trayItems: SystemTray.items ? SystemTray.items.values : []

  readonly property bool hasIndicators: cc.recording || cc.dnd || cc.nightOn || cc.stayAwake
    || cc.keyboardLayout !== ""

  // What the panel drives lives in components/OmarchyControls.qml, the chips'
  // reads in components/OmarchyStatus.qml. The panel keeps the same names for
  // both, so its body does not care where they come from.
  readonly property var controls: host.omarchyControls
  readonly property var powerProfiles: controls.powerProfiles
  readonly property string activeProfile: controls.activeProfile
  readonly property var profileLabels: controls.profileLabels
  readonly property var profileIcons: controls.profileIcons
  readonly property bool brightnessAvailable: controls.brightnessAvailable
  readonly property int brightness: controls.brightness
  readonly property bool gameMode: controls.gameMode
  readonly property string keyboardLayout: controls.keyboardLayout
  readonly property string keyboardDevice: controls.keyboardDevice
  readonly property bool recording: controls.recording
  readonly property int nightMin: controls.nightMin
  readonly property int nightMax: controls.nightMax
  readonly property int nightTemp: controls.nightTemp
  function setNightTemp(k) { controls.setNightTemp(k) }
  function cycleLayout() { controls.cycleLayout() }
  function setProfile(name) { controls.setProfile(name) }
  function setGameMode(on) { controls.setGameMode(on) }
  function setBrightness(v) { controls.setBrightness(v) }
  // The chips' status reads live in components/OmarchyStatus.qml; the panel
  // keeps the same names so its body does not care where they come from.
  readonly property var status: host.omarchyStatus
  readonly property bool dictating: status.dictating
  readonly property int reminderCount: status.reminderCount
  readonly property string reminderTooltip: status.reminderTooltip
  readonly property bool updatesAvailable: status.updatesAvailable
  readonly property string updatesText: status.updatesText
  readonly property int agentsActive: status.agentsActive

  // Weather comes from the island's one shared service (components/Weather.qml),
  // so the chip and the Weather page never ask about the same place twice.
  readonly property var weather: cc.host.weather

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

  Timer {
    interval: 4000
    repeat: true
    running: cc.active
    onTriggered: cc.status.refreshLive()
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
  readonly property var nightlight: controls.nightlight
  readonly property bool dnd: notifications ? !!notifications.doNotDisturb : false
  readonly property bool nightOn: controls.nightOn

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
  Timer { id: dictationRefresh; interval: 700; onTriggered: cc.status.refreshDictation() }
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
    cc.controls.setRecording(false)
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
    // Bring the saved warmth back when the filter comes on.
    if (next) cc.controls.restartNightTemp()
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
  // Brightness and the power profiles are driven through
  // components/OmarchyControls.qml, aliased above.
  onActiveChanged: {
    if (!active) {
      // Leaving the panel must not leave a tray menu behind for next time.
      cc.closeTrayMenu()
      return
    }
    Qt.callLater(function() { cc.forceActiveFocus() })
    cc.controls.loadStoredTemp()
    cc.controls.refresh()
    cc.status.refresh()
    cc.weather.refresh()
  }
  spacing: 8

  // Esc goes back; at the control center itself there is nowhere left to go,
  // so it does nothing (the Win/Super key closes the island).
  Keys.onEscapePressed: {
    if (cc.trayMenuItem !== null) cc.closeTrayMenu()
    else cc.host.goBack()
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
    // A tile is a button: its title is what a screen reader should say.
    Accessible.role: Accessible.Button
    Accessible.name: t.title
    Accessible.description: t.subtitle
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
    Behavior on scale { NumberAnimation { duration: cc.host.motionInstant; easing.type: cc.host.easeStandard } }

    Rectangle {
      id: badge
      anchors.left: parent.left
      anchors.leftMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      width: 36; height: 36; radius: 18
      color: t.checked ? cc.accent : cc.host.withAlpha(cc.text, 0.1)
      Behavior on color { ColorAnimation { duration: cc.animDuration; easing.type: cc.host.easeStandard } }
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
    // The round buttons are icon-only, so the words come from the caller.
    property string accessibleName: ""
    signal clicked()
    Accessible.role: Accessible.Button
    Accessible.name: r.accessibleName
    Accessible.checked: r.checked

    Layout.preferredWidth: 52
    Layout.preferredHeight: 52
    radius: 26
    color: checked ? cc.accent : cc.tile
    border.width: checked ? 0 : 1
    border.color: cc.border
    Behavior on border.width { NumberAnimation { duration: cc.animDuration; easing.type: cc.host.easeStandard } }
    scale: roundMouse.pressed ? 0.94 : 1
    Behavior on color { ColorAnimation { duration: cc.animDuration; easing.type: cc.host.easeStandard } }
    Behavior on scale { NumberAnimation { duration: cc.host.motionInstant; easing.type: cc.host.easeStandard } }
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
        NumberAnimation { duration: cc.host.motionInstant; easing.type: cc.host.easeStandard }
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
    // A chip is a button; `on` is the state it reports.
    Accessible.role: Accessible.Button
    Accessible.name: chip.label
    Accessible.checked: chip.on
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
    Behavior on color { ColorAnimation { duration: cc.animDuration; easing.type: cc.host.easeStandard } }

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
        Behavior on color { ColorAnimation { duration: cc.animDuration; easing.type: cc.host.easeStandard } }
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: chip.label !== ""
        text: chip.label
        color: chip.ink
        font.family: "Adwaita Sans"
        font.pixelSize: 11
        font.weight: chip.on ? Font.DemiBold : Font.Normal
        Behavior on color { ColorAnimation { duration: cc.animDuration; easing.type: cc.host.easeStandard } }
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
        Behavior on rotation { NumberAnimation { duration: cc.animDuration; easing.type: cc.host.easeStandard } }
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
          accessibleName: "Settings"
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
          accessibleName: "Night light"
          icon: "󰖔"
          checked: cc.nightOn
          visible: !!cc.nightlight
          onClicked: cc.toggleNightlight()
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
              cc.setBrightness(v * 100)
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
                Behavior on color { ColorAnimation { duration: cc.animDuration; easing.type: cc.host.easeStandard } }
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
                Behavior on color { ColorAnimation { duration: cc.animDuration; easing.type: cc.host.easeStandard } }
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
                // Recording starts through the Omarchy menu and stops through
                // the capture helper, so the chip needs both to be any use.
                visible: cc.host.hasHelper("omarchy-menu")
                  && cc.host.hasHelper("omarchy-capture-screenrecording")
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
                visible: cc.weather.chipLabel() !== ""
                icon: "󰖐"
                label: cc.weather.chipLabel()
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
              CcChip {
                visible: cc.host.shelfCount > 0
                icon: "󰉋"
                label: cc.host.shelfCount + (cc.host.shelfCount === 1 ? " item" : " items")
                on: true
                onClicked: cc.host.view = "shelf"
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
                accessibleName: "Night light warmth"
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

        // One control with a tab per profile, instead of three separate
        // buttons.
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 38
          radius: 13
          color: cc.well

          RowLayout {
            anchors.fill: parent
            anchors.margins: 3
            spacing: 3

            Repeater {
              model: cc.powerProfiles
              delegate: Rectangle {
                id: profile
                required property var modelData
                readonly property bool selected: modelData === cc.activeProfile

                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 10
                color: profile.selected ? cc.accent : "transparent"
                Behavior on color { ColorAnimation { duration: cc.animDuration; easing.type: cc.host.easeStandard } }

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
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: cc.setProfile(profile.modelData)
                }
              }
            }
          }
        }
      }

      // ---------- Notifications ----------

      Rectangle {
        Layout.fillWidth: true
        // 18 -> 26: the list ends with a bottom inset of its own instead of
        // sitting on the card's edge.
        Layout.preferredHeight: notificationBody.implicitHeight + 26
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
              Behavior on color { ColorAnimation { duration: cc.animDuration; easing.type: cc.host.easeStandard } }
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
            // The list's real height, not a fixed window: the sections scroller
            // above is what moves a long panel, and a second cap here would
            // hide the rows past the fourth and cut the last one in half. Not
            // interactive, so the wheel reaches that scroller instead of being
            // swallowed by a nested flickable.
            Layout.preferredHeight: contentHeight
            interactive: false
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
              color: noteMouse.containsMouse ? cc.host.withAlpha(cc.text, 0.12) : cc.noteRow

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
