import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "../../components"

// The Audio page: pick the output and input, choose which physical port they
// use, test the speakers channel by channel, and set a level per running
// application. Opened from the Output/Input pills in the control center.
ColumnLayout {
  id: audio
  required property var host
  property bool active: false

  readonly property color text: host.colorText
  readonly property color textMuted: host.colorMuted
  readonly property color well: host.withAlpha(host.colorText, 0.1)
  readonly property int animDuration: 180 * host.motionScale

  // ---------- PipeWire nodes ----------

  function allNodes() { return Pipewire.nodes ? Pipewire.nodes.values : [] }

  readonly property var sinks: {
    var out = [], list = allNodes()
    for (var i = 0; i < list.length; i++) {
      var n = list[i]
      if (n && n.isSink && !n.isStream && n.audio) out.push(n)
    }
    return out
  }
  // A monitor is a source too, but it is the speakers fed back into the mic
  // list; it does not belong in an input picker.
  function isMonitor(n) {
    return /\.monitor$/.test(String(n.name || "")) || /^Monitor of /.test(String(n.description || ""))
  }
  readonly property var sources: {
    var out = [], list = allNodes()
    for (var i = 0; i < list.length; i++) {
      var n = list[i]
      if (!n || n.isStream || n.isSink || !n.audio) continue
      if ((n.type & PwNodeType.Source) === 0) continue
      if (isMonitor(n)) continue
      out.push(n)
    }
    return out
  }
  // Application streams (playback and capture), the per-app mixer.
  readonly property var streams: {
    var out = [], list = allNodes()
    for (var i = 0; i < list.length; i++) {
      var n = list[i]
      if (n && n.isStream && n.audio) out.push(n)
    }
    out.sort(function(a, b) { return Number(a.id) - Number(b.id) })
    return out
  }
  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var source: Pipewire.defaultAudioSource

  function nodeName(n) {
    if (!n) return ""
    return String(n.description || n.nickname || n.name || "Device")
  }
  function streamName(n) {
    var p = n.properties || ({})
    return String(p["application.name"] || p["media.name"] || n.description || n.name || "Application")
  }
  function streamDetail(n) {
    var p = n.properties || ({})
    var media = String(p["media.name"] || "")
    if (media !== "" && media !== streamName(n)) return media
    return n.isSink ? "Playback" : "Recording"
  }

  // ---------- Ports ----------
  //
  // PipeWire does not hand ports to QML, so they come from pactl. The JSON is
  // read once per open and after every switch.
  property var sinkInfo: ({})
  property var sourceInfo: ({})
  function portsFor(node, info) {
    if (!node) return []
    var row = info[String(node.name || "")]
    return row && row.ports ? row.ports : []
  }
  function activePortFor(node, info) {
    if (!node) return ""
    var row = info[String(node.name || "")]
    return row ? String(row.active_port || "") : ""
  }
  function prettyPort(port) {
    var described = String(port.description || "")
    if (described !== "" && described !== "(null)") return described
    return String(port.name || "")
      .replace(/^(analog|digital|hdmi|iec958|usb)-(output|input)-/i, "")
      .replace(/[-_]+/g, " ")
      .replace(/\b\w/g, function(c) { return c.toUpperCase() })
  }
  Process {
    id: sinkInfoRead
    command: ["pactl", "-f", "json", "list", "sinks"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var rows = JSON.parse(String(text || "[]"))
          var map = ({})
          for (var i = 0; i < rows.length; i++) map[String(rows[i].name || "")] = rows[i]
          audio.sinkInfo = map
        } catch (e) { audio.sinkInfo = ({}) }
      }
    }
  }
  Process {
    id: sourceInfoRead
    command: ["pactl", "-f", "json", "list", "sources"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var rows = JSON.parse(String(text || "[]"))
          var map = ({})
          for (var i = 0; i < rows.length; i++) map[String(rows[i].name || "")] = rows[i]
          audio.sourceInfo = map
        } catch (e) { audio.sourceInfo = ({}) }
      }
    }
  }
  Process {
    id: portWrite
    onExited: {
      if (!sinkInfoRead.running) sinkInfoRead.running = true
      if (!sourceInfoRead.running) sourceInfoRead.running = true
    }
  }
  function setSinkPort(node, port) {
    if (!node || !port) return
    portWrite.command = ["pactl", "set-sink-port", String(node.name || ""), String(port)]
    portWrite.running = true
  }
  function setSourcePort(node, port) {
    if (!node || !port) return
    portWrite.command = ["pactl", "set-source-port", String(node.name || ""), String(port)]
    portWrite.running = true
  }

  // Which device row has its ports open, by node name.
  property string expandedName: ""

  // ---------- Test tone ----------

  readonly property string toneLeft: String(Qt.resolvedUrl("../../assets/tone-left.wav")).replace(/^file:\/\//, "")
  readonly property string toneRight: String(Qt.resolvedUrl("../../assets/tone-right.wav")).replace(/^file:\/\//, "")
  Process { id: toneProcess }
  function playTone(channel) {
    if (toneProcess.running || !audio.sink) return
    var file = channel === 2 ? audio.toneRight : audio.toneLeft
    toneProcess.command = ["pw-play", "--target", String(audio.sink.name || ""), file]
    toneProcess.running = true
  }

  onActiveChanged: {
    if (!active) return
    Qt.callLater(function() { audio.forceActiveFocus() })
    if (!sinkInfoRead.running) sinkInfoRead.running = true
    if (!sourceInfoRead.running) sourceInfoRead.running = true
  }

  spacing: 10

  Keys.onEscapePressed: host.view = "controls"

  IslandNav {
    Layout.fillWidth: true
    host: audio.host
    title: "Audio"
    onBack: audio.host.view = "controls"
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

      // ---------- Output ----------
      IslandGroup {
        host: audio.host
        title: "Output"

        Repeater {
          model: audio.sinks
          delegate: ColumnLayout {
            id: sinkRow
            required property var modelData
            readonly property bool isDefault: modelData === audio.sink
            readonly property bool open: audio.expandedName === String(modelData.name || "")
            readonly property var ports: audio.portsFor(modelData, audio.sinkInfo)

            Layout.fillWidth: true
            spacing: 0

            Item {
              Layout.fillWidth: true
              Layout.preferredHeight: 56

              Text {
                id: sinkGlyph
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                text: sinkRow.isDefault ? "󰓃" : "󰓄"
                color: sinkRow.isDefault ? audio.host.colorAccent : audio.text
                font.family: audio.host.fontFamily
                font.pixelSize: 18
              }
              Column {
                anchors.left: sinkGlyph.right
                anchors.leftMargin: 12
                anchors.right: sinkTrailing.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                  width: parent.width
                  text: audio.nodeName(sinkRow.modelData)
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  color: audio.text
                  font.family: "Adwaita Sans"
                  font.pixelSize: 14
                  font.weight: sinkRow.isDefault ? Font.DemiBold : Font.Normal
                }
                Text {
                  width: parent.width
                  text: sinkRow.isDefault ? "Default" : "Tap to use"
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  color: sinkRow.isDefault ? audio.host.colorAccent : audio.textMuted
                  font.family: "Adwaita Sans"
                  font.pixelSize: 11
                }
              }
              Row {
                id: sinkTrailing
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Text {
                  visible: sinkRow.ports.length > 0
                  text: "󰅂"
                  rotation: sinkRow.open ? 90 : 0
                  color: audio.textMuted
                  font.family: audio.host.fontFamily
                  font.pixelSize: 13
                  Behavior on rotation { NumberAnimation { duration: audio.animDuration; easing.type: Easing.OutCubic } }
                }
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (!sinkRow.isDefault) Pipewire.preferredDefaultAudioSink = sinkRow.modelData
                  audio.expandedName = sinkRow.open ? "" : String(sinkRow.modelData.name || "")
                }
              }
            }

            // Test tone and the physical ports, for the device in use.
            ColumnLayout {
              Layout.fillWidth: true
              Layout.leftMargin: 16
              Layout.rightMargin: 16
              Layout.bottomMargin: sinkRow.isDefault ? 10 : 0
              visible: sinkRow.open
              spacing: 6

              RowLayout {
                Layout.fillWidth: true
                spacing: 8
                IslandButton {
                  host: audio.host
                  label: "󰓃  Test left"
                  onClicked: audio.playTone(1)
                }
                IslandButton {
                  host: audio.host
                  label: "󰓄  Test right"
                  onClicked: audio.playTone(2)
                }
              }

              Repeater {
                model: sinkRow.ports
                delegate: Rectangle {
                  id: sinkPortRow
                  required property var modelData
                  readonly property bool chosen: String(modelData.name || "") === audio.activePortFor(sinkRow.modelData, audio.sinkInfo)
                  readonly property bool usable: String(modelData.availability || "") !== "not available"

                  Layout.fillWidth: true
                  Layout.preferredHeight: 34
                  radius: 10
                  color: sinkPortMouse.containsMouse ? audio.well : "transparent"
                  opacity: sinkPortRow.usable ? 1 : 0.45

                  Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: audio.prettyPort(sinkPortRow.modelData)
                    color: sinkPortRow.chosen ? audio.host.colorAccent : audio.text
                    font.family: "Adwaita Sans"
                    font.pixelSize: 12
                    font.weight: sinkPortRow.chosen ? Font.DemiBold : Font.Normal
                  }
                  Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    visible: sinkPortRow.chosen
                    text: "󰄬"
                    color: audio.host.colorAccent
                    font.family: audio.host.fontFamily
                    font.pixelSize: 14
                  }
                  MouseArea {
                    id: sinkPortMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: sinkPortRow.usable
                    cursorShape: Qt.PointingHandCursor
                    onClicked: audio.setSinkPort(sinkRow.modelData, sinkPortRow.modelData.name)
                  }
                }
              }
            }
          }
        }

        Text {
          Layout.fillWidth: true
          Layout.topMargin: 18
          Layout.bottomMargin: 18
          visible: audio.sinks.length === 0
          horizontalAlignment: Text.AlignHCenter
          text: "No output devices"
          color: audio.textMuted
          font.family: "Adwaita Sans"
          font.pixelSize: 12
        }
      }

      // ---------- Input ----------
      IslandGroup {
        host: audio.host
        title: "Input"

        Repeater {
          model: audio.sources
          delegate: ColumnLayout {
            id: sourceRow
            required property var modelData
            readonly property bool isDefault: modelData === audio.source
            readonly property bool open: audio.expandedName === String(modelData.name || "")
            readonly property var ports: audio.portsFor(modelData, audio.sourceInfo)

            Layout.fillWidth: true
            spacing: 0

            Item {
              Layout.fillWidth: true
              Layout.preferredHeight: 56

              Text {
                id: sourceGlyph
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                text: "󰍬"
                color: sourceRow.isDefault ? audio.host.colorAccent : audio.text
                font.family: audio.host.fontFamily
                font.pixelSize: 18
              }
              Column {
                anchors.left: sourceGlyph.right
                anchors.leftMargin: 12
                anchors.right: sourceToggle.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                  width: parent.width
                  text: audio.nodeName(sourceRow.modelData)
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  color: audio.text
                  font.family: "Adwaita Sans"
                  font.pixelSize: 14
                  font.weight: sourceRow.isDefault ? Font.DemiBold : Font.Normal
                }
                Text {
                  width: parent.width
                  text: sourceRow.isDefault ? "Default" : "Tap to use"
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  color: sourceRow.isDefault ? audio.host.colorAccent : audio.textMuted
                  font.family: "Adwaita Sans"
                  font.pixelSize: 11
                }
              }
              IslandSwitch {
                id: sourceToggle
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                host: audio.host
                checked: sourceRow.isDefault
                onToggled: Pipewire.preferredDefaultAudioSource = sourceRow.modelData
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (!sourceRow.isDefault) Pipewire.preferredDefaultAudioSource = sourceRow.modelData
                  audio.expandedName = sourceRow.open ? "" : String(sourceRow.modelData.name || "")
                }
              }
            }

            ColumnLayout {
              Layout.fillWidth: true
              Layout.leftMargin: 16
              Layout.rightMargin: 16
              Layout.bottomMargin: 10
              visible: sourceRow.open && sourceRow.ports.length > 0
              spacing: 6

              Repeater {
                model: sourceRow.ports
                delegate: Rectangle {
                  id: sourcePortRow
                  required property var modelData
                  readonly property bool chosen: String(modelData.name || "") === audio.activePortFor(sourceRow.modelData, audio.sourceInfo)
                  readonly property bool usable: String(modelData.availability || "") !== "not available"

                  Layout.fillWidth: true
                  Layout.preferredHeight: 34
                  radius: 10
                  color: sourcePortMouse.containsMouse ? audio.well : "transparent"
                  opacity: sourcePortRow.usable ? 1 : 0.45

                  Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: audio.prettyPort(sourcePortRow.modelData)
                    color: sourcePortRow.chosen ? audio.host.colorAccent : audio.text
                    font.family: "Adwaita Sans"
                    font.pixelSize: 12
                    font.weight: sourcePortRow.chosen ? Font.DemiBold : Font.Normal
                  }
                  Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    visible: sourcePortRow.chosen
                    text: "󰄬"
                    color: audio.host.colorAccent
                    font.family: audio.host.fontFamily
                    font.pixelSize: 14
                  }
                  MouseArea {
                    id: sourcePortMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: sourcePortRow.usable
                    cursorShape: Qt.PointingHandCursor
                    onClicked: audio.setSourcePort(sourceRow.modelData, sourcePortRow.modelData.name)
                  }
                }
              }
            }
          }
        }

        Text {
          Layout.fillWidth: true
          Layout.topMargin: 18
          Layout.bottomMargin: 18
          visible: audio.sources.length === 0
          horizontalAlignment: Text.AlignHCenter
          text: "No input devices"
          color: audio.textMuted
          font.family: "Adwaita Sans"
          font.pixelSize: 12
        }
      }

      // ---------- Applications ----------
      IslandGroup {
        host: audio.host
        title: "Applications"

        Text {
          Layout.fillWidth: true
          Layout.topMargin: 18
          Layout.bottomMargin: 18
          visible: audio.streams.length === 0
          horizontalAlignment: Text.AlignHCenter
          text: "Nothing playing"
          color: audio.textMuted
          font.family: "Adwaita Sans"
          font.pixelSize: 12
        }

        Repeater {
          model: audio.streams
          delegate: ColumnLayout {
            id: streamRow
            required property var modelData
            readonly property bool muted: !!(modelData.audio && modelData.audio.muted)

            Layout.fillWidth: true
            spacing: 2

            Item {
              Layout.fillWidth: true
              Layout.preferredHeight: 30
              Text {
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.right: streamMute.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: audio.streamName(streamRow.modelData)
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: audio.text
                font.family: "Adwaita Sans"
                font.pixelSize: 13
                font.weight: Font.Medium
              }
              Text {
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                visible: !streamRow.muted
                text: audio.streamDetail(streamRow.modelData)
                color: audio.textMuted
                font.family: "Adwaita Sans"
                font.pixelSize: 11
              }
              Text {
                id: streamMute
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                visible: streamRow.muted
                text: "󰖁"
                color: audio.host.colorUrgent
                font.family: audio.host.fontFamily
                font.pixelSize: 14
              }
            }

            IslandSlider {
              host: audio.host
              Layout.fillWidth: true
              Layout.leftMargin: 16
              Layout.rightMargin: 16
              Layout.bottomMargin: 8
              value: streamRow.modelData.audio ? streamRow.modelData.audio.volume : 0
              valueText: Math.round((streamRow.muted ? 0 : (streamRow.modelData.audio ? streamRow.modelData.audio.volume : 0)) * 100) + "%"
              onMoved: function(v) {
                if (!streamRow.modelData.audio) return
                streamRow.modelData.audio.volume = v
                if (streamRow.modelData.audio.muted && v > 0) streamRow.modelData.audio.muted = false
              }
            }
          }
        }
      }
    }
  }
}
