import QtQuick
import QtQuick.Layouts
import "../../components"

// The island's own settings, laid out like iOS Settings: a navigation bar with
// a back button, then inset grouped rows with switches and segmented pickers.
// Opened from the control center's gear button; Esc goes back to it. Changes
// apply live and are saved to ~/.config/omarchy/island.json (see Island.qml).
ColumnLayout {
  id: settingsView
  required property var host
  property bool active: false
  readonly property var settings: host.settings
  readonly property string version: host.manifest && host.manifest.version ? String(host.manifest.version) : "—"

  // Tabs replace the old single long scroll.
  property string tab: "look"
  readonly property var tabs: [
    { id: "look", label: "Look" },
    { id: "pill", label: "Pill" },
    { id: "system", label: "System" },
    { id: "about", label: "About" }
  ]
  function cycleTab(delta) {
    var i = 0
    for (var k = 0; k < tabs.length; k++) if (tabs[k].id === tab) { i = k; break }
    tab = tabs[(i + delta + tabs.length) % tabs.length].id
  }
  onTabChanged: scroller.contentY = 0

  // Everything back to the shipped value. nightTemp is included even though it
  // has no row here, so a reset is genuinely a reset.
  function resetDefaults() {
    var s = settingsView.settings
    s.motionScale = 1.5
    s.hoverLift = true
    s.clock24h = true
    s.clockSeconds = false
    s.notch = false
    s.solidBlack = false
    s.keepShelf = false
    s.workspaceDots = true
    s.batteryBadge = true
    s.mediaPill = true
    s.volumeHud = true
    s.clipboard = true
    s.downloads = true
    s.systemUpdates = true
    s.systemMonitor = false
    s.timerChime = true
    s.timerNotify = true
    s.hideFullscreen = true
    s.autoMonitorHot = true
    s.askAi = "chatgpt"
    s.bannerSeconds = 5
    s.pomodoro = false
    s.nightTemp = 4000
    settingsView.host.announce("Settings reset")
  }

  readonly property color text: host.colorText
  readonly property color textMuted: host.colorMuted
  readonly property color card: host.withAlpha(host.colorText, 0.07)
  readonly property color well: host.withAlpha(host.colorText, 0.1)
  readonly property color divider: host.withAlpha(host.colorText, 0.08)
  readonly property int animDuration: 180 * host.motionScale

  spacing: 8
  onActiveChanged: if (active) Qt.callLater(function() { settingsView.forceActiveFocus() })
  Keys.onEscapePressed: host.goBack()
  // The list is long now, so the keyboard moves it as well as the wheel.
  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Down) { scroller.flick(0, -600); event.accepted = true }
    else if (event.key === Qt.Key_Up) { scroller.flick(0, 600); event.accepted = true }
    else if (event.key === Qt.Key_PageDown) { scroller.contentY = Math.min(scroller.contentHeight - scroller.height, scroller.contentY + scroller.height); event.accepted = true }
    else if (event.key === Qt.Key_PageUp) { scroller.contentY = Math.max(0, scroller.contentY - scroller.height); event.accepted = true }
    else if (event.key === Qt.Key_Home) { scroller.contentY = 0; event.accepted = true }
    else if (event.key === Qt.Key_End) { scroller.contentY = Math.max(0, scroller.contentHeight - scroller.height); event.accepted = true }
    else if (event.key === Qt.Key_Left) { settingsView.cycleTab(-1); event.accepted = true }
    else if (event.key === Qt.Key_Right) { settingsView.cycleTab(1); event.accepted = true }
  }

  // iOS switch: accent track when on, white knob sliding across.
  component SettingsSwitch: Rectangle {
    id: sw
    property bool checked: false
    signal toggled(bool checked)
    implicitWidth: 46
    implicitHeight: 28
    radius: 14
    color: checked ? settingsView.host.colorAccent : settingsView.well
    Behavior on color { ColorAnimation { duration: settingsView.animDuration; easing.type: Easing.OutCubic } }
    Rectangle {
      width: 24; height: 24; radius: 12
      y: 2
      x: sw.checked ? sw.width - width - 2 : 2
      // The track's ink, so a white accent does not hide a white knob.
      color: sw.checked ? settingsView.host.colorAccentText : "#ffffff"
      Behavior on color { ColorAnimation { duration: settingsView.animDuration } }
      Behavior on x { NumberAnimation { duration: settingsView.animDuration; easing.type: Easing.OutCubic } }
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: sw.toggled(!sw.checked)
    }
  }

  // iOS segmented control for a few fixed values.
  component SettingsSegments: Rectangle {
    id: seg
    property var options: []   // [{ label, value }]
    property var value
    signal picked(var value)
    readonly property int index: {
      for (var i = 0; i < options.length; i++) if (options[i].value === value) return i
      return -1
    }
    implicitWidth: options.length * (options.length > 3 ? 70 : 62) + 4
    implicitHeight: 28
    radius: 9
    color: settingsView.well
    Rectangle {
      visible: seg.index >= 0
      y: 2
      height: parent.height - 4
      width: (parent.width - 4) / Math.max(1, seg.options.length)
      x: 2 + Math.max(0, seg.index) * width
      radius: 7
      color: settingsView.host.withAlpha(settingsView.text, 0.2)
      Behavior on x { NumberAnimation { duration: settingsView.animDuration; easing.type: Easing.OutCubic } }
    }
    Row {
      anchors.fill: parent
      anchors.margins: 2
      Repeater {
        model: seg.options
        delegate: Item {
          required property var modelData
          width: parent.width / seg.options.length
          height: parent.height
          Text {
            anchors.centerIn: parent
            text: modelData.label
            color: settingsView.text
            font.family: "Adwaita Sans"
            font.pixelSize: 12
            font.weight: seg.value === modelData.value ? Font.DemiBold : Font.Normal
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: seg.picked(modelData.value)
          }
        }
      }
    }
  }

  // One row of a group: label (and optional detail) on the left, a control
  // on the right, and a hairline under every row but the last.
  component SettingsRow: Item {
    id: row
    property string label: ""
    property string detail: ""
    property bool last: false
    default property alias control: slot.data
    Layout.fillWidth: true
    implicitHeight: detail !== "" ? 58 : 48
    Column {
      anchors.left: parent.left
      anchors.leftMargin: 16
      anchors.right: slot.left
      anchors.rightMargin: 12
      anchors.verticalCenter: parent.verticalCenter
      spacing: 2
      Text {
        width: parent.width
        text: row.label
        elide: Text.ElideRight
        color: settingsView.text
        font.family: "Adwaita Sans"
        font.pixelSize: 14
        font.letterSpacing: -0.2
      }
      Text {
        width: parent.width
        visible: row.detail !== ""
        text: row.detail
        elide: Text.ElideRight
        color: settingsView.textMuted
        font.family: "Adwaita Sans"
        font.pixelSize: 11
      }
    }
    Item {
      id: slot
      anchors.right: parent.right
      anchors.rightMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      width: childrenRect.width
      height: childrenRect.height
    }
    Rectangle {
      visible: !row.last
      anchors.left: parent.left
      anchors.leftMargin: 16
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: 1
      color: settingsView.divider
    }
  }

  // A read-only value on the trailing side of a row.
  component SettingsValue: Text {
    color: settingsView.textMuted
    font.family: "Adwaita Sans"
    font.pixelSize: 13
    font.weight: Font.DemiBold
  }

  // A titled inset group of rows.
  component SettingsGroup: ColumnLayout {
    id: group
    property string title: ""
    default property alias rows: groupBody.data
    Layout.fillWidth: true
    spacing: 6
    Text {
      Layout.leftMargin: 16
      text: group.title.toUpperCase()
      color: settingsView.textMuted
      font.family: "Adwaita Sans"
      font.pixelSize: 11
      font.letterSpacing: 0.4
    }
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: groupBody.implicitHeight
      radius: 18
      color: settingsView.card
      border.width: 1
      border.color: settingsView.host.colorBorder
      ColumnLayout {
        id: groupBody
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0
      }
    }
  }

  // ---------- Navigation bar ----------

  Item {
    Layout.fillWidth: true
    Layout.preferredHeight: 36
    Layout.bottomMargin: 4
    Rectangle {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: 32; height: 32; radius: 16
      color: backMouse.containsMouse ? settingsView.host.withAlpha(settingsView.text, 0.16) : settingsView.well
      Behavior on color { ColorAnimation { duration: settingsView.animDuration } }
      Text {
        anchors.centerIn: parent
        text: "󰅁"
        color: settingsView.text
        font.family: settingsView.host.fontFamily
        font.pixelSize: 18
      }
      MouseArea {
        id: backMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: settingsView.host.view = "controls"
      }
    }
    Text {
      anchors.centerIn: parent
      text: "Settings"
      color: settingsView.text
      font.family: "Adwaita Sans"
      font.pixelSize: 16
      font.weight: Font.DemiBold
      font.letterSpacing: -0.3
    }
  }

  // ---------- Tabs ----------

  Row {
    Layout.fillWidth: true
    Layout.bottomMargin: 4
    spacing: 4
    Repeater {
      model: settingsView.tabs
      delegate: Item {
        required property var modelData
        width: (parent.width - 12) / 4
        height: 30
        Rectangle {
          anchors.fill: parent
          radius: 9
          color: settingsView.tab === modelData.id
            ? settingsView.host.withAlpha(settingsView.text, 0.18)
            : "transparent"
          border.width: 1
          border.color: settingsView.tab === modelData.id ? "transparent" : settingsView.divider
          Behavior on color { ColorAnimation { duration: settingsView.animDuration } }
          Text {
            anchors.centerIn: parent
            text: modelData.label
            color: settingsView.tab === modelData.id ? settingsView.text : settingsView.textMuted
            font.family: "Adwaita Sans"
            font.pixelSize: 12
            font.weight: settingsView.tab === modelData.id ? Font.DemiBold : Font.Normal
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: settingsView.tab = modelData.id
          }
        }
      }
    }
  }

  // ---------- Groups ----------

  // The groups scroll under the tabs once they outgrow the island's window
  // (which is 800 px tall).
  Flickable {
    id: scroller
    Layout.fillWidth: true
    Layout.preferredHeight: Math.min(groups.implicitHeight, 680)
    contentHeight: groups.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
      id: groups
      width: scroller.width
      spacing: 8

      SettingsGroup {
        visible: settingsView.tab === "look"
        title: "Appearance"
        SettingsRow {
          label: "Animation Speed"
          SettingsSegments {
            options: [{ label: "Fast", value: 1 }, { label: "Normal", value: 1.5 }, { label: "Relaxed", value: 2 }]
            value: settingsView.settings.motionScale
            onPicked: function(v) { settingsView.settings.motionScale = v }
          }
        }
        SettingsRow {
          label: "Hover Lift"
          detail: "The clock pill lifts slightly under the pointer"
          SettingsSwitch {
            checked: settingsView.settings.hoverLift
            onToggled: function(on) { settingsView.settings.hoverLift = on }
          }
        }
        SettingsRow {
          label: "Notch Style"
          detail: "Attach the island to the top edge, like a MacBook notch"
          SettingsSwitch {
            checked: settingsView.settings.notch
            onToggled: function(on) { settingsView.settings.notch = on }
          }
        }
        SettingsRow {
          label: "Solid Black"
          detail: "Opaque black pill with white ink, like the original"
          SettingsSwitch {
            checked: settingsView.settings.solidBlack
            onToggled: function(on) { settingsView.settings.solidBlack = on }
          }
        }
        SettingsRow {
          label: "24-Hour Clock"
          SettingsSwitch {
            checked: settingsView.settings.clock24h
            onToggled: function(on) { settingsView.settings.clock24h = on }
          }
        }
        SettingsRow {
          label: "Clock Seconds"
          detail: "Count seconds in the resting clock"
          SettingsSwitch {
            checked: settingsView.settings.clockSeconds
            onToggled: function(on) { settingsView.settings.clockSeconds = on }
          }
        }
        SettingsRow {
          label: "Workspace Dots"
          detail: "Workspace indicators on the resting pill"
          SettingsSwitch {
            checked: settingsView.settings.workspaceDots
            onToggled: function(on) { settingsView.settings.workspaceDots = on }
          }
        }
        SettingsRow {
          label: "Battery"
          detail: "Charge glyph and percentage on the resting pill"
          last: true
          SettingsSwitch {
            checked: settingsView.settings.batteryBadge
            onToggled: function(on) { settingsView.settings.batteryBadge = on }
          }
        }
      }

      SettingsGroup {
        visible: settingsView.tab === "pill"
        title: "Live Activities"
        SettingsRow {
          label: "Now Playing"
          detail: "Show the cover and sound wave while media plays"
          SettingsSwitch {
            checked: settingsView.settings.mediaPill
            onToggled: function(on) { settingsView.settings.mediaPill = on }
          }
        }
        SettingsRow {
          label: "Volume HUD"
          detail: "Show the level when the volume changes"
          SettingsSwitch {
            checked: settingsView.settings.volumeHud
            onToggled: function(on) { settingsView.settings.volumeHud = on }
          }
        }
        SettingsRow {
          label: "Clipboard"
          detail: "Show what you copied for a moment"
          SettingsSwitch {
            checked: settingsView.settings.clipboard
            onToggled: function(on) { settingsView.settings.clipboard = on }
          }
        }
        SettingsRow {
          label: "Downloads"
          detail: "Show browser downloads in progress on the pill"
          SettingsSwitch {
            checked: settingsView.settings.downloads
            onToggled: function(on) { settingsView.settings.downloads = on }
          }
        }
        SettingsRow {
          label: "System Updates"
          detail: "Show pacman, yay, paru, and Omarchy updates on the pill"
          SettingsSwitch {
            checked: settingsView.settings.systemUpdates
            onToggled: function(on) { settingsView.settings.systemUpdates = on }
          }
        }
        SettingsRow {
          label: "System Monitor"
          detail: "Keep CPU and temperature on the resting pill"
          SettingsSwitch {
            checked: settingsView.settings.systemMonitor
            onToggled: function(on) { settingsView.settings.systemMonitor = on }
          }
        }
        SettingsRow {
          label: "Timer Chime"
          detail: "Play a sound when a timer finishes"
          SettingsSwitch {
            checked: settingsView.settings.timerChime
            onToggled: function(on) { settingsView.settings.timerChime = on }
          }
        }
        SettingsRow {
          label: "Timer Notification"
          detail: "Post a desktop notification when a timer finishes"
          last: true
          SettingsSwitch {
            checked: settingsView.settings.timerNotify
            onToggled: function(on) { settingsView.settings.timerNotify = on }
          }
        }
      }

      SettingsGroup {
        visible: settingsView.tab === "system"
        title: "Behavior"
        SettingsRow {
          label: "Hide in Fullscreen"
          detail: "Slide the pill away while a window is fullscreen"
          SettingsSwitch {
            checked: settingsView.settings.hideFullscreen
            onToggled: function(on) { settingsView.settings.hideFullscreen = on }
          }
        }
        SettingsRow {
          label: "Monitor When Hot"
          detail: "Show CPU and temperature at 85 °C or 95 % load, unpinned"
          last: true
          SettingsSwitch {
            checked: settingsView.settings.autoMonitorHot
            onToggled: function(on) { settingsView.settings.autoMonitorHot = on }
          }
        }
      }

      SettingsGroup {
        visible: settingsView.tab === "system"
        title: "Shelf"
        SettingsRow {
          label: "Keep Shelf"
          detail: "Restore parked items after a shell restart"
          last: true
          SettingsSwitch {
            checked: settingsView.settings.keepShelf
            onToggled: function(on) { settingsView.settings.keepShelf = on }
          }
        }
      }

      SettingsGroup {
        visible: settingsView.tab === "system"
        title: "Search"
        SettingsRow {
          label: "Ask With"
          detail: "Answers launcher questions in the island"
          last: true
          SettingsSegments {
            options: [{ label: "Claude", value: "claude" }, { label: "Codex", value: "chatgpt" }, { label: "None", value: "none" }]
            value: settingsView.settings.askAi
            onPicked: function(v) { settingsView.settings.askAi = v }
          }
        }
      }

      SettingsGroup {
        visible: settingsView.tab === "system"
        title: "Notifications"
        SettingsRow {
          label: "Banner Duration"
          last: true
          SettingsSegments {
            options: [{ label: "3 s", value: 3 }, { label: "5 s", value: 5 }, { label: "8 s", value: 8 }]
            value: settingsView.settings.bannerSeconds
            onPicked: function(v) { settingsView.settings.bannerSeconds = v }
          }
        }
      }

      SettingsGroup {
        visible: settingsView.tab === "about"
        title: "About"
        SettingsRow {
          label: "Version"
          SettingsValue { text: settingsView.version }
        }
        SettingsRow {
          label: "Settings File"
          detail: "~/.config/omarchy/island.json"
        }
        SettingsRow {
          label: "Reset to Defaults"
          detail: "Put every switch and value back the way it shipped"
          last: true
          IslandButton {
            host: settingsView.host
            label: "Reset"
            danger: true
            onClicked: settingsView.resetDefaults()
          }
        }
      }
    }
  }
}
