import QtQuick
import QtQuick.Layouts
import "../../components"

// The Timer page: a countdown with a few presets, pause and add-a-minute, and
// the Pomodoro switch. While it runs, the same countdown shows on the resting
// pill as a live activity.
ColumnLayout {
  id: timerView
  required property var host
  property bool active: false

  readonly property var timer: host.timer
  readonly property color text: host.colorText
  readonly property color textMuted: host.colorMuted
  readonly property color well: host.withAlpha(host.colorText, 0.1)
  readonly property int animDuration: host.motionBase
  readonly property var presets: [
    { label: "5 min", seconds: 300, name: "Break" },
    { label: "10 min", seconds: 600, name: "Timer" },
    { label: "25 min", seconds: 1500, name: "Focus" },
    { label: "45 min", seconds: 2700, name: "Focus" }
  ]

  property bool customError: false

  // Accepts "12:30" (mm:ss), "1:02:30" (h:mm:ss), "1h 30m", "90s", "15m", or a
  // bare number of minutes. Anything unreadable is a zero, which the caller
  // shows as an error.
  function parseDuration(raw) {
    var s = String(raw || "").trim().toLowerCase()
    if (s === "") return 0
    if (s.indexOf(":") !== -1) {
      var parts = s.split(":").map(function(p) { return parseInt(p, 10) || 0 })
      if (parts.length === 3) return parts[0] * 3600 + parts[1] * 60 + parts[2]
      if (parts.length === 2) return parts[0] * 60 + parts[1]
      return 0
    }
    var h = /(\d+)\s*(h|ч)/.exec(s)
    var m = /(\d+)\s*(m|м|min)/.exec(s)
    var sec = /(\d+)\s*(s|с|sec)/.exec(s)
    if (h || m || sec)
      return (h ? parseInt(h[1], 10) * 3600 : 0)
        + (m ? parseInt(m[1], 10) * 60 : 0)
        + (sec ? parseInt(sec[1], 10) : 0)
    var n = parseInt(s, 10)
    return isNaN(n) ? 0 : n * 60
  }

  function startCustom() {
    var seconds = timerView.parseDuration(customInput.text)
    if (seconds <= 0) {
      timerView.customError = true
      return
    }
    timerView.customError = false
    timerView.timer.start(seconds, "Timer")
    customInput.text = ""
  }

  spacing: 10
  onActiveChanged: if (active) Qt.callLater(function() {
    timerView.forceActiveFocus()
    // Opening the page puts the cursor in the custom field, so a time can be
    // typed right away; the presets are still one click.
    customInput.forceActiveFocus()
  })
  Keys.onEscapePressed: host.goBack()

  IslandNav {
    Layout.fillWidth: true
    host: timerView.host
    title: "Timer"
    onBack: timerView.host.view = "controls"
  }

  Flickable {
    id: scroller
    Layout.fillWidth: true
    Layout.preferredHeight: Math.min(groups.implicitHeight, 560)
    contentHeight: groups.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
      id: groups
      width: scroller.width
      spacing: 8

      IslandGroup {
        host: timerView.host
        title: timerView.timer.running ? timerView.timer.label : "Timer"

        Text {
          Layout.fillWidth: true
          Layout.topMargin: 22
          horizontalAlignment: Text.AlignHCenter
          text: timerView.timer.running ? timerView.timer.formatted() : "00:00"
          color: timerView.text
          font.family: "Adwaita Sans"
          font.pixelSize: 42
          font.weight: Font.DemiBold
          font.features: { "tnum": 1 }
          font.letterSpacing: -1
        }

        Item {
          Layout.fillWidth: true
          Layout.leftMargin: 18
          Layout.rightMargin: 18
          Layout.topMargin: 6
          Layout.bottomMargin: 16
          Layout.preferredHeight: 5
          Rectangle {
            anchors.fill: parent
            radius: 2.5
            color: timerView.well
            Rectangle {
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: parent.width * timerView.timer.progress
              radius: 2.5
              color: timerView.host.colorAccent
              Behavior on width { NumberAnimation { duration: timerView.host.motionPanel; easing.type: timerView.host.easeStandard } }
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          Layout.leftMargin: 16
          Layout.rightMargin: 16
          Layout.bottomMargin: 16
          spacing: 8
          visible: timerView.timer.running

          IslandButton {
            host: timerView.host
            label: timerView.timer.paused ? "󰐊  Resume" : "󰏤  Pause"
            onClicked: timerView.timer.togglePause()
          }
          IslandButton {
            host: timerView.host
            label: "+1 min"
            onClicked: timerView.timer.add(60)
          }
          Item { Layout.fillWidth: true }
          IslandButton {
            host: timerView.host
            label: "Stop"
            danger: true
            onClicked: timerView.timer.stop()
          }
        }

        RowLayout {
          Layout.fillWidth: true
          Layout.leftMargin: 16
          Layout.rightMargin: 16
          Layout.bottomMargin: 16
          spacing: 8
          visible: !timerView.timer.running

          Repeater {
            model: timerView.presets
            delegate: IslandButton {
              required property var modelData
              host: timerView.host
              label: modelData.label
              onClicked: timerView.timer.start(modelData.seconds, modelData.name)
            }
          }
        }
      }

      IslandGroup {
        host: timerView.host
        title: "Custom"

        Item {
          Layout.fillWidth: true
          Layout.leftMargin: 16
          Layout.rightMargin: 16
          Layout.topMargin: 8
          Layout.bottomMargin: 12
          implicitHeight: 36

          Rectangle {
            id: customField
            anchors.left: parent.left
            anchors.right: customStart.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            height: 36
            radius: 18
            color: timerView.well
            border.width: 1
            border.color: timerView.customError ? timerView.host.colorUrgent : timerView.host.colorBorder
            Behavior on border.color { ColorAnimation { duration: timerView.animDuration; easing.type: timerView.host.easeStandard } }

            Text {
              id: customGlyph
              anchors.left: parent.left
              anchors.leftMargin: 12
              anchors.verticalCenter: parent.verticalCenter
              text: "󰔛"
              color: timerView.textMuted
              font.family: timerView.host.fontFamily
              font.pixelSize: 14
            }
            TextInput {
              id: customInput
              anchors.left: customGlyph.right
              anchors.leftMargin: 8
              anchors.right: parent.right
              anchors.rightMargin: 12
              anchors.verticalCenter: parent.verticalCenter
              color: timerView.text
              selectionColor: timerView.host.withAlpha(timerView.host.colorAccent, 0.4)
              selectedTextColor: timerView.text
              font.family: "Adwaita Sans"
              font.pixelSize: 13
              clip: true
              onTextChanged: timerView.customError = false
              onAccepted: timerView.startCustom()
              Keys.onEscapePressed: function(event) {
                customInput.focus = false
                timerView.forceActiveFocus()
                event.accepted = true
              }
              Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                visible: customInput.text === ""
                text: "mm:ss, 15m, 1h 30m…"
                color: timerView.textMuted
                font: customInput.font
              }
            }
          }
          IslandButton {
            id: customStart
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            host: timerView.host
            label: "Start"
            onClicked: timerView.startCustom()
          }
        }
      }

      IslandGroup {
        host: timerView.host
        title: "Pomodoro"

        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: 58
          Column {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.right: pomodoroSwitch.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text {
              text: "Alternate focus and break"
              color: timerView.text
              font.family: "Adwaita Sans"
              font.pixelSize: 14
            }
            Text {
              width: parent.width
              text: "When a 25-minute focus ends, a 5-minute break starts by itself (and back)"
              color: timerView.textMuted
              font.family: "Adwaita Sans"
              font.pixelSize: 11
              wrapMode: Text.WordWrap
            }
          }
          IslandSwitch {
            id: pomodoroSwitch
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            host: timerView.host
            checked: !!timerView.host.settings.pomodoro
            onToggled: function(on) { timerView.host.settings.pomodoro = on }
          }
        }
      }
    }
  }
}
