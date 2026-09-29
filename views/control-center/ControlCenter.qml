import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Widgets

// The expanded "controls" surface: two rows of toggle pills with a round
// button at the end of each, Sound and Display cards with sliders, and the
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
  readonly property var outputs: {
    var nodes = Pipewire.nodes ? Pipewire.nodes.values : []
    return nodes.filter(function(n) { return n && n.isSink && !n.isStream && n.audio })
  }
  property bool outputsOpen: false

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
  function setProfile(name) {
    if (name === cc.activeProfile) return
    cc.activeProfile = name   // optimistic; profilesRead confirms
    profileWrite.command = ["omarchy-powerprofiles-set", "autodetect", name]
    profileWrite.running = true
  }

  // --- Brightness (the Display card hides when the output has no control) ---
  property bool brightnessAvailable: false
  property int brightness: 0
  onActiveChanged: {
    if (!active) { outputsOpen = false; return }
    Qt.callLater(function() { cc.forceActiveFocus() })
    if (!brightnessRead.running) brightnessRead.running = true
    if (!gameModeRead.running) gameModeRead.running = true
    if (!profilesRead.running) profilesRead.running = true
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

  spacing: 10

  // Esc closes the control center.
  Keys.onEscapePressed: cc.host.view = "rest"

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
    signal clicked()

    Layout.fillWidth: true
    Layout.preferredWidth: 1
    Layout.preferredHeight: 62
    radius: 31
    color: cc.tile
    border.width: 1
    border.color: cc.border
    opacity: available ? 1 : 0.5
    scale: tileMouse.pressed ? 0.97 : 1
    Behavior on scale { NumberAnimation { duration: 120 * cc.host.motionScale; easing.type: Easing.OutCubic } }

    Rectangle {
      id: badge
      anchors.left: parent.left
      anchors.leftMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      width: 42; height: 42; radius: 21
      color: t.checked ? cc.accent : cc.host.withAlpha(cc.text, 0.1)
      Behavior on color { ColorAnimation { duration: cc.animDuration; easing.type: Easing.OutCubic } }
      Text {
        anchors.centerIn: parent
        text: t.icon
        color: t.checked ? cc.accentInk : cc.text
        font.family: cc.iconFont
        font.pixelSize: 19
      }
    }
    Column {
      anchors.left: badge.right
      anchors.leftMargin: 11
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
        font.pixelSize: 14
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
        font.pixelSize: 12
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
      font.pixelSize: 15
    }
    MouseArea {
      id: tileMouse
      anchors.fill: parent
      enabled: t.available
      cursorShape: Qt.PointingHandCursor
      onClicked: t.clicked()
    }
  }

  // Round button at the end of a toggle row; accent-filled when on.
  component CcRound: Rectangle {
    id: r
    property string icon: ""
    property bool checked: false
    signal clicked()

    Layout.preferredWidth: 62
    Layout.preferredHeight: 62
    radius: 31
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
      font.pixelSize: 20
    }
    MouseArea {
      id: roundMouse
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: r.clicked()
    }
  }

  component CcSlider: Rectangle {
    id: s
    property string icon: ""
    // Shown at the right end; kept clear of the fill by its own colour swap.
    property string valueText: ""
    property real value: 0
    signal moved(real value)

    readonly property real fraction: Math.max(0, Math.min(1, s.value))
    readonly property real fillWidth: Math.max(s.height, s.width * s.fraction)

    Layout.fillWidth: true
    Layout.preferredHeight: 46
    radius: 23
    color: cc.well
    clip: true

    Rectangle {
      height: parent.height
      radius: parent.radius
      width: s.fillWidth
      color: cc.accent
      Behavior on width {
        enabled: !sliderMouse.pressed
        NumberAnimation { duration: 140 * cc.host.motionScale; easing.type: Easing.OutCubic }
      }
    }
    Text {
      anchors.left: parent.left
      anchors.leftMargin: 16
      anchors.verticalCenter: parent.verticalCenter
      text: s.icon
      // Over the accent fill or over the track, whichever is behind it.
      color: s.fillWidth > 46 ? cc.accentInk : cc.text
      font.family: cc.iconFont
      font.pixelSize: 18
    }
    Text {
      visible: s.valueText !== ""
      anchors.right: parent.right
      anchors.rightMargin: 16
      anchors.verticalCenter: parent.verticalCenter
      text: s.valueText
      color: s.fillWidth > s.width - 54 ? cc.accentInk : cc.textMuted
      font.family: "Adwaita Sans"
      font.pixelSize: 12
      font.weight: Font.DemiBold
      font.features: { "tnum": 1 }
    }
    MouseArea {
      id: sliderMouse
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      function apply(x) { s.moved(Math.max(0, Math.min(1, x / width))) }
      onPressed: function(e) { apply(e.x) }
      onPositionChanged: function(e) { if (pressed) apply(e.x) }
      onWheel: function(e) { s.moved(Math.max(0, Math.min(1, s.value + (e.angleDelta.y > 0 ? 0.05 : -0.05)))) }
    }
  }

  // Section card with a title row (and an optional › button) over content.
  component CcSection: Rectangle {
    id: sec
    property string title: ""
    property bool showChevron: false
    property bool chevronOpen: false
    signal chevronClicked()
    default property alias content: body.data

    Layout.fillWidth: true
    Layout.preferredHeight: body.implicitHeight + 52
    radius: 26
    color: cc.card
    border.width: 1
    border.color: cc.border

    Text {
      anchors.left: parent.left
      anchors.leftMargin: 16
      anchors.top: parent.top
      anchors.topMargin: 13
      text: sec.title
      color: cc.text
      font.family: "Adwaita Sans"
      font.pixelSize: 14
      font.weight: Font.DemiBold
      font.letterSpacing: -0.2
    }
    Rectangle {
      visible: sec.showChevron
      anchors.right: parent.right
      anchors.rightMargin: 10
      anchors.top: parent.top
      anchors.topMargin: 8
      width: 26; height: 26; radius: 13
      color: cc.well
      Text {
        anchors.centerIn: parent
        text: "󰅂"
        rotation: sec.chevronOpen ? 90 : 0
        color: cc.textMuted
        font.family: cc.iconFont
        font.pixelSize: 15
        Behavior on rotation { NumberAnimation { duration: cc.animDuration; easing.type: Easing.OutCubic } }
      }
      MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sec.chevronClicked() }
    }
    ColumnLayout {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: 42
      anchors.leftMargin: 10
      anchors.rightMargin: 10
      spacing: 6
    }
  }

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
      onClicked: cc.host.view = "wifi"
    }
    CcTile {
      icon: "󰍶"
      title: "Focus"
      subtitle: cc.dnd ? "On" : "Off"
      checked: cc.dnd
      available: !!cc.notifications
      onClicked: cc.notifications.setDoNotDisturb(!cc.dnd)
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
      onClicked: cc.nightlight.setNightlight(!cc.nightOn)
    }
  }

  // ---------- Sound / Display ----------

  CcSection {
    title: "Sound"
    visible: !!(cc.sink && cc.sink.audio)
    showChevron: cc.outputs.length > 1
    chevronOpen: cc.outputsOpen
    onChevronClicked: cc.outputsOpen = !cc.outputsOpen

    CcSlider {
      icon: cc.muted || cc.volume <= 0 ? "󰖁" : cc.volume < 0.34 ? "󰕿" : cc.volume < 0.67 ? "󰖀" : "󰕾"
      valueText: Math.round((cc.muted ? 0 : cc.volume) * 100) + "%"
      value: cc.muted ? 0 : cc.volume
      onMoved: function(v) {
        cc.sink.audio.volume = v
        if (cc.sink.audio.muted && v > 0) cc.sink.audio.muted = false
      }
    }
    Text {
      Layout.fillWidth: true
      Layout.leftMargin: 8
      Layout.rightMargin: 8
      Layout.topMargin: 2
      visible: text !== ""
      text: cc.sink ? String(cc.sink.description || cc.sink.nickname || cc.sink.name || "") : ""
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: cc.textMuted
      font.family: "Adwaita Sans"
      font.pixelSize: 11
    }
    // Output picker, revealed by the › button.
    Repeater {
      model: cc.outputsOpen ? cc.outputs : []
      delegate: Rectangle {
        id: outputRow
        required property var modelData
        readonly property bool isDefault: modelData === cc.sink
        Layout.fillWidth: true
        Layout.preferredHeight: 34
        radius: 12
        color: outputMouse.containsMouse ? cc.well : "transparent"
        Text {
          anchors.left: parent.left
          anchors.leftMargin: 10
          anchors.right: outputCheck.left
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          text: String(outputRow.modelData.description || outputRow.modelData.nickname || outputRow.modelData.name || "")
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: outputRow.isDefault ? cc.text : cc.textMuted
          font.family: "Adwaita Sans"
          font.pixelSize: 12
        }
        Text {
          id: outputCheck
          anchors.right: parent.right
          anchors.rightMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          visible: outputRow.isDefault
          text: "󰄬"
          color: cc.accent
          font.family: cc.iconFont
          font.pixelSize: 14
        }
        MouseArea {
          id: outputMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: Pipewire.preferredDefaultAudioSink = outputRow.modelData
        }
      }
    }
  }

  CcSection {
    title: "Display"
    visible: cc.brightnessAvailable
    CcSlider {
      icon: "󰃠"
      valueText: cc.brightness + "%"
      value: cc.brightness / 100
      onMoved: function(v) {
        cc.brightness = Math.round(v * 100)
        brightnessDebounce.restart()
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
          Layout.preferredHeight: 44
          radius: 15
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
              font.pixelSize: 15
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

    // Omarchy keeps a separate choice per power source; say which one this is.
    Text {
      Layout.fillWidth: true
      Layout.leftMargin: 8
      Layout.rightMargin: 8
      Layout.topMargin: 2
      text: UPower.onBattery ? "Saved for battery" : "Saved while plugged in"
      color: cc.textMuted
      font.family: "Adwaita Sans"
      font.pixelSize: 11
    }
  }

  // ---------- Notifications ----------

  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: notificationBody.implicitHeight + 20
    radius: 26
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
          font.pixelSize: 14
          font.weight: Font.DemiBold
          font.letterSpacing: -0.2
        }
        Item { Layout.fillWidth: true }
        // iOS's grey capsule button.
        Rectangle {
          visible: cc.host.history.length > 0
          implicitWidth: clearLabel.implicitWidth + 20
          implicitHeight: 24
          radius: 12
          color: clearMouse.containsMouse ? cc.host.withAlpha(cc.text, 0.16) : cc.well
          Behavior on color { ColorAnimation { duration: cc.animDuration } }
          Text {
            id: clearLabel
            anchors.centerIn: parent
            text: "Clear"
            color: cc.text
            font.family: "Adwaita Sans"
            font.pixelSize: 12
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
        Layout.preferredHeight: Math.min(contentHeight, 240)
        clip: true
        spacing: 8
        boundsBehavior: Flickable.StopAtBounds
        model: cc.host.history
        delegate: Rectangle {
          id: note
          required property var modelData
          readonly property string appName: String(modelData.app || modelData.summary || "?")
          width: ListView.view.width
          height: noteBody.implicitHeight + 24
          radius: 20
          color: noteMouse.containsMouse && modelData.isActive ? cc.host.withAlpha(cc.text, 0.12) : cc.card

          MouseArea {
            id: noteMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: !!note.modelData.isActive
            onClicked: cc.host.notificationCommand("invokeKey", note.modelData)
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
            anchors.leftMargin: 12
            anchors.top: parent.top
            anchors.topMargin: 12
            width: 34; height: 34; radius: 9
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
            anchors.leftMargin: 12
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
                font.pixelSize: 14
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
                font.pixelSize: 12
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
              font.pixelSize: 13
            }
          }
          Text {
            anchors.right: parent.right
            anchors.rightMargin: 13
            anchors.top: parent.top
            anchors.topMargin: 12
            text: "󰅖"
            color: closeMouse.containsMouse ? cc.text : cc.textMuted
            font.family: cc.iconFont
            font.pixelSize: 13
            MouseArea { id: closeMouse; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; onClicked: cc.host.dismissNotification(note.modelData) }
          }
        }
      }
    }
  }
}
