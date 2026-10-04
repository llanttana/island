import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import "../../components"

// The Bluetooth page: pair, connect, and forget devices. Opened from the
// control center's Bluetooth tile; the back button returns there.
//
// Device rows are plain snapshots; pairing is handed to the same
// `omarchy-bluetooth-device` helper the stock panel uses, so trust and power
// handling stay identical. That helper is a one-shot command, so a row's
// spinner is cleared by watching the device's state rather than an exit code.
ColumnLayout {
  id: bt
  required property var host
  property bool active: false

  readonly property color text: host.colorText
  readonly property color textMuted: host.colorMuted
  readonly property color well: host.withAlpha(host.colorText, 0.1)
  readonly property color divider: host.withAlpha(host.colorText, 0.08)
  readonly property int animDuration: 180 * host.motionScale

  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property bool enabled: !!(adapter && adapter.enabled)
  readonly property bool discovering: !!(adapter && adapter.discovering)

  function isUuidLike(value) {
    var t = String(value || "").trim()
    if (t === "") return false
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(t)
      || /^[0-9a-f]{32}$/i.test(t)
      || /^0x[0-9a-f]{4,32}$/i.test(t)
      || /^0000[0-9a-f]{4}-0000-1000-8000-00805f9b34fb$/i.test(t)
  }
  function isAddressLike(value) {
    return /^([0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i.test(String(value || "").trim())
  }
  function deviceLabel(d) {
    return String((d && (d.deviceName || d.name)) || "").trim()
  }
  function hasHumanName(d) {
    var label = deviceLabel(d)
    return label !== "" && !isUuidLike(label) && !isAddressLike(label)
  }

  // { connected: [...], known: [...], other: [...] } sorted by name.
  readonly property var groups: {
    var values = Bluetooth.devices ? Bluetooth.devices.values : []
    var connected = [], known = [], other = []
    for (var i = 0; i < values.length; i++) {
      var d = values[i]
      if (!d || !hasHumanName(d)) continue
      var row = {
        address: String(d.address || ""),
        label: deviceLabel(d),
        connected: !!d.connected,
        known: !!(d.paired || d.bonded || d.trusted),
        pairing: !!d.pairing,
        batteryAvailable: !!d.batteryAvailable,
        battery: d.battery !== undefined ? Number(d.battery) : 0
      }
      if (row.connected) connected.push(row)
      else if (row.known) known.push(row)
      else other.push(row)
    }
    function byLabel(a, b) { return a.label.localeCompare(b.label) }
    connected.sort(byLabel)
    known.sort(byLabel)
    other.sort(byLabel)
    return { connected: connected, known: known, other: other }
  }

  function deviceForAddress(address) {
    var lists = [groups.connected, groups.known, groups.other]
    for (var i = 0; i < lists.length; i++)
      for (var j = 0; j < lists[i].length; j++)
        if (lists[i][j].address === address) return lists[i][j]
    return null
  }

  // ---------- Scanning ----------

  function startScan() {
    if (!adapter || !adapter.enabled) return
    if (!adapter.discovering) adapter.discovering = true
  }
  function stopScan() {
    if (adapter && adapter.discovering) adapter.discovering = false
  }
  function rescan() {
    stopScan()
    Qt.callLater(function() { bt.startScan() })
  }
  // BlueZ needs a moment after power-on before discovery sticks.
  Timer { id: scanKick; interval: 700; onTriggered: bt.startScan() }

  // ---------- Device actions ----------

  property string pendingAddress: ""
  property string pendingAction: ""   // pair | connect | disconnect | forget

  function clearPending() {
    pendingAddress = ""
    pendingAction = ""
  }

  function actionSettled(row) {
    var d = bt.deviceForAddress(row.address)
    if (bt.pendingAction === "forget") return !d || !d.known
    if (bt.pendingAction === "disconnect") return !d || !d.connected
    return !!(d && d.connected)
  }

  function runAction(row, action) {
    if (pendingAddress !== "" && pendingAddress !== row.address) return
    pendingAddress = row.address
    pendingAction = action
    actionTimeout.restart()
    Quickshell.execDetached(["omarchy-bluetooth-device", action, row.address])
  }

  function rowClicked(row) {
    if (pendingAddress === row.address) return
    if (row.connected) runAction(row, "disconnect")
    else if (row.known) runAction(row, "connect")
    else runAction(row, "pair")
  }

  function forget(row) {
    if (pendingAddress === row.address) return
    runAction(row, "forget")
  }

  Timer {
    id: actionTimeout
    interval: 26000
    onTriggered: bt.clearPending()
  }
  // The helper has no exit signal we can use; settle on the device's state.
  Timer {
    id: actionWatch
    interval: 500
    repeat: true
    running: bt.pendingAddress !== ""
    onTriggered: {
      var row = bt.deviceForAddress(bt.pendingAddress)
      if (!row || bt.actionSettled(row)) bt.clearPending()
    }
  }

  onActiveChanged: {
    if (active) {
      Qt.callLater(function() { bt.forceActiveFocus() })
      // Same as Wi-Fi: discovery is what costs the shell frames, so it waits
      // for the opening animation to finish.
      scanStart.restart()
    } else {
      scanStart.stop()
      stopScan()
      clearPending()
    }
  }
  Timer {
    id: scanStart
    interval: 420
    onTriggered: bt.startScan()
  }
  Component.onDestruction: if (adapter && adapter.discovering) adapter.discovering = false

  spacing: 10

  Keys.onEscapePressed: host.goBack()

  // ---------- Rows ----------

  component DeviceRow: Item {
    id: device
    required property var modelData
    required property int index
    property int groupLength: 0

    readonly property var row: modelData
    readonly property bool last: index === groupLength - 1
    readonly property bool busy: bt.pendingAddress === row.address
    readonly property bool showForget: row.known && !busy && (rowMouse.containsMouse || forgetMouse.containsMouse)

    Layout.fillWidth: true
    implicitHeight: 56

    Text {
      id: glyph
      anchors.left: parent.left
      anchors.leftMargin: 16
      anchors.verticalCenter: parent.verticalCenter
      text: device.row.connected ? "󰂱" : "󰂯"
      color: device.row.connected ? bt.host.colorAccent : bt.text
      font.family: bt.host.fontFamily
      font.pixelSize: 18
    }

    Column {
      anchors.left: glyph.right
      anchors.leftMargin: 12
      anchors.right: trailing.left
      anchors.rightMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      spacing: 1

      Text {
        width: parent.width
        text: device.row.label
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: bt.text
        font.family: "Adwaita Sans"
        font.pixelSize: 14
        font.weight: device.row.connected ? Font.DemiBold : Font.Normal
      }
      Text {
        width: parent.width
        text: {
          if (device.busy) return bt.pendingAction === "forget" ? "Forgetting…"
            : bt.pendingAction === "disconnect" ? "Disconnecting…"
            : bt.pendingAction === "pair" ? "Pairing…" : "Connecting…"
          if (device.row.connected) return device.row.batteryAvailable
            ? "Connected · " + Math.round(device.row.battery * 100) + "%" : "Connected"
          if (device.row.known) return device.row.batteryAvailable
            ? "Saved · " + Math.round(device.row.battery * 100) + "%" : "Saved"
          return "Available"
        }
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: bt.textMuted
        font.family: "Adwaita Sans"
        font.pixelSize: 11
      }
    }

    Row {
      id: trailing
      anchors.right: parent.right
      anchors.rightMargin: 16
      anchors.verticalCenter: parent.verticalCenter
      spacing: 8

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: device.busy
        text: "󰑐"
        color: bt.textMuted
        font.family: bt.host.fontFamily
        font.pixelSize: 15
        // On the render loop, so it spins at the display's refresh rate. Only
        // alive while an action is in flight.
        RotationAnimation on rotation {
          running: device.busy
          from: 0
          to: 360
          duration: 900
          loops: Animation.Infinite
        }
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: device.row.connected && !device.busy
        text: "󰄬"
        color: bt.host.colorAccent
        font.family: bt.host.fontFamily
        font.pixelSize: 15
      }
      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        visible: device.showForget
        width: 26
        height: 26
        radius: 13
        color: forgetMouse.containsMouse ? bt.host.withAlpha(bt.text, 0.18) : bt.host.withAlpha(bt.text, 0.1)
        Behavior on color { ColorAnimation { duration: bt.animDuration } }
        Text {
          anchors.centerIn: parent
          text: "󰅖"
          color: bt.textMuted
          font.family: bt.host.fontFamily
          font.pixelSize: 13
        }
        MouseArea {
          id: forgetMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: bt.forget(device.row)
        }
      }
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: bt.rowClicked(device.row)
    }

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: 16
      anchors.bottom: parent.bottom
      height: 1
      color: bt.divider
      visible: !device.last
    }
  }

  // ---------- Navigation ----------

  IslandNav {
    Layout.fillWidth: true
    host: bt.host
    title: "Bluetooth"
    onBack: bt.host.view = "controls"

    Rectangle {
      width: 32
      height: 32
      radius: 16
      visible: bt.enabled
      color: rescanMouse.containsMouse ? bt.host.withAlpha(bt.text, 0.16) : bt.well
      Behavior on color { ColorAnimation { duration: bt.animDuration } }
      Text {
        anchors.centerIn: parent
        // Deliberately static: discovery runs the whole time the page is open,
        // so anything animated here would repaint the island forever. The
        // "Scanning for devices…" line and the appearing rows are the feedback.
        text: "󰒕"
        color: bt.text
        font.family: bt.host.fontFamily
        font.pixelSize: 17
      }
      MouseArea {
        id: rescanMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: bt.rescan()
      }
    }
  }

  Flickable {
    id: scroller
    Layout.fillWidth: true
    Layout.preferredHeight: Math.min(groupsColumn.implicitHeight, 600)
    contentHeight: groupsColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
      id: groupsColumn
      width: scroller.width
      spacing: 8

      IslandGroup {
        host: bt.host
        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: 52
          Text {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: bt.adapter ? "Bluetooth" : "No adapter"
            color: bt.text
            font.family: "Adwaita Sans"
            font.pixelSize: 14
          }
          IslandSwitch {
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            host: bt.host
            checked: bt.enabled
            enabled: !!bt.adapter
            onToggled: function(on) {
              if (bt.adapter) bt.adapter.enabled = on
              if (on) scanKick.restart()
            }
          }
        }
      }

      IslandGroup {
        host: bt.host
        title: "Connected"
        visible: bt.groups.connected.length > 0
        Repeater {
          model: bt.groups.connected
          delegate: DeviceRow { groupLength: bt.groups.connected.length }
        }
      }

      IslandGroup {
        host: bt.host
        title: "My Devices"
        visible: bt.groups.known.length > 0
        Repeater {
          model: bt.groups.known
          delegate: DeviceRow { groupLength: bt.groups.known.length }
        }
      }

      IslandGroup {
        host: bt.host
        title: "Available"
        visible: bt.groups.other.length > 0
        Repeater {
          model: bt.groups.other
          delegate: DeviceRow { groupLength: bt.groups.other.length }
        }
      }

      // Empty / off states.
      ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: bt.enabled && (bt.groups.connected.length + bt.groups.known.length + bt.groups.other.length) > 0 ? 0 : 20
        Layout.bottomMargin: 12
        visible: !bt.enabled || (bt.groups.connected.length + bt.groups.known.length + bt.groups.other.length) === 0
        spacing: 6

        Text {
          Layout.fillWidth: true
          horizontalAlignment: Text.AlignHCenter
          text: !bt.adapter ? "No Bluetooth adapter"
            : !bt.enabled ? "Bluetooth is off"
            : bt.discovering ? "Scanning for devices…" : "No devices found"
          color: bt.text
          font.family: "Adwaita Sans"
          font.pixelSize: 14
          font.weight: Font.DemiBold
        }
        Text {
          Layout.fillWidth: true
          horizontalAlignment: Text.AlignHCenter
          visible: !bt.enabled && !!bt.adapter
          text: "Turn it on to pair a device"
          color: bt.textMuted
          font.family: "Adwaita Sans"
          font.pixelSize: 12
        }
      }
    }
  }
}
