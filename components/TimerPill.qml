import QtQuick

// Timer live activity: the countdown where the clock sits, with the timer's
// name on the trailing side and a hairline progress bar along the foot of the
// pill. Visible while a timer runs.
Item {
  id: pill
  required property var host
  readonly property var timer: host.timer
  readonly property bool shown: host.timerPill

  opacity: shown ? 1 : 0
  visible: opacity > 0.01
  Behavior on opacity { NumberAnimation { duration: opacity > 0.5 ? 70 : 150 * pill.host.motionScale; easing.type: Easing.InOutQuad } }

  Text {
    anchors.left: parent.left
    anchors.leftMargin: 14
    anchors.verticalCenter: parent.verticalCenter
    text: pill.timer.paused ? "󰏤" : "󰔛"
    color: pill.host.colorAccent
    font.family: pill.host.fontFamily
    font.pixelSize: 15
  }

  Text {
    anchors.centerIn: parent
    text: pill.timer.formatted()
    color: pill.host.ink
    font.family: "Adwaita Sans"
    font.pixelSize: 16
    font.weight: Font.DemiBold
    font.features: { "tnum": 1, "case": 1 }
    font.letterSpacing: -0.4
  }

  Text {
    anchors.right: parent.right
    anchors.rightMargin: 14
    anchors.verticalCenter: parent.verticalCenter
    width: Math.min(120, parent.width / 2 - 40)
    horizontalAlignment: Text.AlignRight
    text: pill.timer.label
    textFormat: Text.PlainText
    elide: Text.ElideRight
    color: pill.host.colorMuted
    font.family: "Adwaita Sans"
    font.pixelSize: 11
  }

  // Hairline progress along the foot: fills as the time is used up.
  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: 3
    color: pill.host.withAlpha(pill.host.colorText, 0.12)
    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: parent.width * pill.timer.progress
      color: pill.host.colorAccent
      Behavior on width { NumberAnimation { duration: 400 * pill.host.motionScale; easing.type: Easing.OutCubic } }
    }
  }
}
