import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Networking
import "../../components"

// The Wi-Fi page: join a network and manage the ones already saved. Opened
// from the control center's Wi-Fi tile; the back button returns there.
//
// Rows are plain snapshots (SSID, signal, flags) rather than live WifiNetwork
// wrappers: a scan can destroy a wrapper while a delegate still holds it,
// which crashes Quickshell. Anything that acts on a network resolves the live
// object again by SSID.
ColumnLayout {
  id: wifi
  required property var host
  property bool active: false

  readonly property color text: host.colorText
  readonly property color textMuted: host.colorMuted
  readonly property color well: host.withAlpha(host.colorText, 0.1)
  readonly property color divider: host.withAlpha(host.colorText, 0.08)
  readonly property int animDuration: 180 * host.motionScale

  // ---------- Adapter ----------

  readonly property var device: {
    var devices = Networking.devices ? Networking.devices.values : []
    var fallback = null
    for (var i = 0; i < devices.length; i++) {
      var d = devices[i]
      if (!d || d.type !== DeviceType.Wifi) continue
      if (d.connected) return d
      if (!fallback) fallback = d
    }
    return fallback
  }
  readonly property bool hardwareEnabled: Networking.wifiHardwareEnabled !== false
  readonly property bool enabled: Networking.wifiEnabled === true

  readonly property var liveNetworks: device && device.networks ? device.networks.values : []

  readonly property var rows: {
    var nets = liveNetworks
    var out = []
    for (var i = 0; i < nets.length; i++) {
      var n = nets[i]
      if (!n || !n.name) continue
      out.push({
        ssid: String(n.name),
        signal: Math.round((n.signalStrength || 0) * 100),
        known: !!n.known,
        connected: !!n.connected,
        security: n.security
      })
    }
    out.sort(function(a, b) {
      if (a.connected !== b.connected) return a.connected ? -1 : 1
      if (a.known !== b.known) return a.known ? -1 : 1
      return b.signal - a.signal
    })
    return out
  }

  function networkForSsid(ssid) {
    var nets = liveNetworks
    for (var i = 0; i < nets.length; i++) if (nets[i] && nets[i].name === ssid) return nets[i]
    return null
  }

  function requiresCredentials(security) {
    return security !== WifiSecurityType.Open && security !== WifiSecurityType.Owe
  }

  function securityLabel(security) {
    if (security === WifiSecurityType.Open) return "Open"
    if (security === WifiSecurityType.Owe) return "Open, encrypted"
    if (security === WifiSecurityType.Wpa2Eap || security === WifiSecurityType.WpaEap) return "Enterprise"
    return "Secured"
  }

  function signalIcon(strength) {
    var icons = ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]
    var index = Math.max(0, Math.min(4, Math.ceil(strength / 20) - 1))
    return icons[index]
  }

  function reasonText(reason) {
    if (reason === ConnectionFailReason.NoSecrets) return "Passphrase required"
    if (reason === ConnectionFailReason.WifiAuthTimeout) return "Wrong password"
    if (reason === ConnectionFailReason.WifiNetworkLost) return "Network lost"
    if (reason === ConnectionFailReason.WifiClientDisconnected) return "Disconnected"
    if (reason === ConnectionFailReason.WifiClientFailed) return "Connection failed"
    return "Couldn't connect"
  }

  // ---------- Actions ----------

  // The SSID a connect is in flight for, and the one that failed last.
  property string busySsid: ""
  property string failureSsid: ""
  property string failureText: ""
  // The SSID whose password box is open, and the one showing its actions.
  property string passwordSsid: ""
  property string detailSsid: ""

  function rescan() {
    if (!device) return
    device.scannerEnabled = false
    Qt.callLater(function() { if (wifi.device) wifi.device.scannerEnabled = true })
  }

  function clearAction() {
    actionTimeout.stop()
    busySsid = ""
    failureSsid = ""
    failureText = ""
  }

  function clearPrompts() {
    passwordSsid = ""
    detailSsid = ""
  }

  function openPassword(ssid) {
    detailSsid = ""
    passwordSsid = ssid
  }

  // Row tap: the connected row opens its actions, a secured network we have no
  // credentials for asks for them, everything else just connects.
  function rowClicked(ssid) {
    var net = networkForSsid(ssid)
    if (!net) return
    failureSsid = ""
    if (net.connected) {
      passwordSsid = ""
      detailSsid = detailSsid === ssid ? "" : ssid
      return
    }
    detailSsid = ""
    if (requiresCredentials(net.security) && !net.known) {
      openPassword(ssid)
      return
    }
    connect(ssid)
  }

  function connect(ssid) {
    var net = networkForSsid(ssid)
    if (!net) return
    clearAction()
    busySsid = ssid
    actionTimeout.restart()
    net.connect()
  }

  function submitPassword(value) {
    var ssid = passwordSsid
    var net = networkForSsid(ssid)
    if (!net || !value) return
    clearAction()
    busySsid = ssid
    actionTimeout.restart()
    passwordSsid = ""
    net.connectWithPsk(value)
  }

  function succeeded() {
    clearAction()
    clearPrompts()
  }

  function fail(ssid, reason) {
    if (busySsid !== ssid) return
    clearAction()
    failureSsid = ssid
    failureText = reasonText(reason)
    // A credentialed network we couldn't join is worth another password.
    var net = networkForSsid(ssid)
    if (net && requiresCredentials(net.security)
        && (reason === ConnectionFailReason.NoSecrets || reason === ConnectionFailReason.WifiAuthTimeout))
      openPassword(ssid)
  }

  function disconnect(ssid) {
    var net = networkForSsid(ssid)
    if (!net) return
    detailSsid = ""
    net.disconnect()
  }

  function forget(ssid) {
    var net = networkForSsid(ssid)
    if (!net) return
    detailSsid = ""
    net.forget()
  }

  Timer {
    id: actionTimeout
    interval: 22000
    onTriggered: if (wifi.busySsid !== "") wifi.fail(wifi.busySsid, -1)
  }

  onActiveChanged: {
    if (active) {
      Qt.callLater(function() { wifi.forceActiveFocus() })
      if (wifi.device) wifi.device.scannerEnabled = true
    } else {
      if (wifi.device) wifi.device.scannerEnabled = false
      clearAction()
      clearPrompts()
    }
  }
  Component.onDestruction: if (device) device.scannerEnabled = false

  spacing: 10

  Keys.onEscapePressed: {
    if (passwordSsid !== "" || detailSsid !== "") { clearPrompts(); return }
    host.view = "controls"
  }

  // ---------- Navigation ----------

  IslandNav {
    Layout.fillWidth: true
    host: wifi.host
    title: "Wi-Fi"
    onBack: wifi.host.view = "controls"

    Rectangle {
      width: 32
      height: 32
      radius: 16
      color: rescanMouse.containsMouse ? wifi.host.withAlpha(wifi.text, 0.16) : wifi.well
      Behavior on color { ColorAnimation { duration: wifi.animDuration } }
      Text {
        anchors.centerIn: parent
        text: "󰑐"
        color: wifi.text
        font.family: wifi.host.fontFamily
        font.pixelSize: 17
      }
      MouseArea {
        id: rescanMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: wifi.rescan()
      }
    }
  }

  Flickable {
    id: scroller
    Layout.fillWidth: true
    Layout.preferredHeight: Math.min(groups.implicitHeight, 600)
    contentHeight: groups.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
      id: groups
      width: scroller.width
      spacing: 8

      IslandGroup {
        host: wifi.host
        title: wifi.hardwareEnabled ? "" : "Hardware switched off"

        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: 52
          Text {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: "Wi-Fi"
            color: wifi.text
            font.family: "Adwaita Sans"
            font.pixelSize: 14
          }
          IslandSwitch {
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            host: wifi.host
            checked: wifi.enabled
            enabled: wifi.hardwareEnabled
            onToggled: function(on) { Networking.wifiEnabled = on }
          }
        }
      }

      IslandGroup {
        host: wifi.host
        title: "Networks"
        visible: wifi.enabled

        Text {
          Layout.fillWidth: true
          Layout.topMargin: 18
          Layout.bottomMargin: 18
          visible: wifi.rows.length === 0
          horizontalAlignment: Text.AlignHCenter
          text: "Scanning for networks…"
          color: wifi.textMuted
          font.family: "Adwaita Sans"
          font.pixelSize: 12
        }

        Repeater {
          model: wifi.rows
          delegate: Rectangle {
            id: netRow
            required property var modelData
            required property int index

            readonly property string ssid: modelData.ssid
            readonly property bool secured: wifi.requiresCredentials(modelData.security)
            readonly property bool isBusy: wifi.busySsid === ssid
            readonly property bool isFailed: wifi.failureSsid === ssid
            readonly property bool passwordOpen: wifi.passwordSsid === ssid
            readonly property bool detailOpen: wifi.detailSsid === ssid

            Layout.fillWidth: true
            implicitHeight: rowContent.implicitHeight
            color: "transparent"

            Column {
              id: rowContent
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              spacing: 0

              Item {
                width: rowContent.width
                height: 56

                Text {
                  id: signalGlyph
                  anchors.left: parent.left
                  anchors.leftMargin: 16
                  anchors.verticalCenter: parent.verticalCenter
                  text: wifi.signalIcon(modelData.signal)
                  color: modelData.connected ? wifi.host.colorAccent : wifi.text
                  font.family: wifi.host.fontFamily
                  font.pixelSize: 18
                }

                Column {
                  anchors.left: signalGlyph.right
                  anchors.leftMargin: 12
                  anchors.right: trailing.left
                  anchors.rightMargin: 10
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 1

                  Text {
                    width: parent.width
                    text: netRow.ssid
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: wifi.text
                    font.family: "Adwaita Sans"
                    font.pixelSize: 14
                    font.weight: netRow.modelData.connected ? Font.DemiBold : Font.Normal
                  }
                  Text {
                    width: parent.width
                    visible: text !== ""
                    text: netRow.isFailed ? wifi.failureText
                      : netRow.isBusy ? "Connecting…"
                      : netRow.modelData.connected ? "Connected"
                      : netRow.modelData.known ? "Saved" : wifi.securityLabel(netRow.modelData.security)
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: netRow.isFailed ? wifi.host.colorUrgent : wifi.textMuted
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
                    visible: netRow.isBusy
                    text: "󰑐"
                    color: wifi.textMuted
                    font.family: wifi.host.fontFamily
                    font.pixelSize: 15
                    RotationAnimation on rotation {
                      running: netRow.isBusy
                      from: 0
                      to: 360
                      duration: 900
                      loops: Animation.Infinite
                    }
                  }
                  Text {
                    visible: netRow.modelData.connected
                    text: "󰄬"
                    color: wifi.host.colorAccent
                    font.family: wifi.host.fontFamily
                    font.pixelSize: 15
                  }
                  Text {
                    visible: netRow.secured && !netRow.modelData.connected && !netRow.isBusy
                    text: "󰌾"
                    color: wifi.textMuted
                    font.family: wifi.host.fontFamily
                    font.pixelSize: 13
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: wifi.rowClicked(netRow.ssid)
                }

                Rectangle {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.leftMargin: 16
                  anchors.bottom: parent.bottom
                  height: 1
                  color: wifi.divider
                  visible: netRow.index < wifi.rows.length - 1
                }
              }

              // Password entry for a secured network we don't have yet.
              RowLayout {
                width: rowContent.width
                visible: netRow.passwordOpen
                spacing: 8
                Layout.bottomMargin: 10
                anchors.leftMargin: 16
                anchors.rightMargin: 16

                Rectangle {
                  Layout.fillWidth: true
                  Layout.preferredHeight: 36
                  Layout.leftMargin: 16
                  radius: 12
                  color: wifi.well
                  TextInput {
                    id: passwordInput
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    color: wifi.text
                    selectionColor: wifi.host.withAlpha(wifi.host.colorAccent, 0.4)
                    selectedTextColor: wifi.text
                    font.family: "Adwaita Sans"
                    font.pixelSize: 13
                    clip: true
                    onVisibleChanged: if (visible) { text = ""; forceActiveFocus() }
                    onAccepted: wifi.submitPassword(text)
                    Keys.onEscapePressed: wifi.clearPrompts()
                    Text {
                      anchors.fill: parent
                      verticalAlignment: Text.AlignVCenter
                      visible: passwordInput.text === ""
                      text: "Password"
                      color: wifi.textMuted
                      font: passwordInput.font
                    }
                  }
                }
                IslandButton {
                  host: wifi.host
                  label: "Join"
                  Layout.rightMargin: 16
                  onClicked: wifi.submitPassword(passwordInput.text)
                }
              }

              // Actions for the network we're on.
              RowLayout {
                width: rowContent.width
                visible: netRow.detailOpen
                spacing: 8
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                Item { Layout.preferredWidth: 16 }
                IslandButton {
                  host: wifi.host
                  label: "Disconnect"
                  onClicked: wifi.disconnect(netRow.ssid)
                }
                IslandButton {
                  host: wifi.host
                  label: "Forget"
                  danger: true
                  onClicked: wifi.forget(netRow.ssid)
                }
                Item { Layout.fillWidth: true }
                Item { Layout.preferredHeight: 10 }
              }

              Item {
                width: rowContent.width
                height: netRow.passwordOpen || netRow.detailOpen ? 10 : 0
              }
            }

            // A row's live network reports when a join failed or landed.
            Connections {
              target: wifi.networkForSsid(netRow.ssid)
              function onConnectionFailed(reason) { wifi.fail(netRow.ssid, reason) }
              function onConnectedChanged() {
                var net = wifi.networkForSsid(netRow.ssid)
                if (net && net.connected && wifi.busySsid === netRow.ssid) wifi.succeeded()
              }
            }
          }
        }
      }

      // Wi-Fi off: point at the switch rather than showing a stale list.
      ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: 20
        Layout.bottomMargin: 12
        visible: !wifi.enabled
        spacing: 6
        Text {
          Layout.fillWidth: true
          horizontalAlignment: Text.AlignHCenter
          text: wifi.hardwareEnabled ? "Wi-Fi is off" : "Hardware switch is off"
          color: wifi.text
          font.family: "Adwaita Sans"
          font.pixelSize: 14
          font.weight: Font.DemiBold
        }
        Text {
          Layout.fillWidth: true
          horizontalAlignment: Text.AlignHCenter
          text: wifi.hardwareEnabled ? "Turn it on to see nearby networks" : "Flip the wireless switch on the keyboard"
          color: wifi.textMuted
          font.family: "Adwaita Sans"
          font.pixelSize: 12
        }
      }
    }
  }
}
