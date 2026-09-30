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
  readonly property int animDuration: 180 * host.motionScale
  readonly property var presets: [
    { label: "5 min", seconds: 300, name: "Break" },
    { label: "10 min", seconds: 600, name: "Timer" },
    { label: "25 min", seconds: 1500, name: "Focus" },
    { label: "45 min", seconds: 2700, name: "Focus" }
  ]

  spacing: 10
  onActiveChanged: if (active) Qt.callLater(function() { timerView.forceActiveFocus() })
  Keys.onEscapePressed: host.view = "controls"

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
              Behavior on width { NumberAnimation { duration: 400 * timerView.host.motionScale; easing.type: Easing.OutCubic } }
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
