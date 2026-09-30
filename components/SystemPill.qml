import QtQuick

// System-monitor live activity: CPU load leading, temperature (or memory when
// there is no sensor) trailing, with the clock still centred. Shown when the
// monitor is pinned, or on its own when the machine runs hot.
Item {
  id: pill
  required property var host
  readonly property var stats: host.systemStats
  readonly property bool shown: host.systemPill

  opacity: shown ? 1 : 0
  visible: opacity > 0.01
  Behavior on opacity { NumberAnimation { duration: opacity > 0.5 ? 70 : 150 * pill.host.motionScale; easing.type: Easing.InOutQuad } }

  Row {
    anchors.left: parent.left
    anchors.leftMargin: 14
    anchors.verticalCenter: parent.verticalCenter
    spacing: 5
    Text {
      text: "󰍛"
      color: pill.host.colorAccent
      font.family: pill.host.fontFamily
      font.pixelSize: 14
    }
    Text {
      text: Math.round(pill.stats.cpu) + "%"
      color: pill.host.ink
      font.family: "Adwaita Sans"
      font.pixelSize: 13
      font.weight: Font.DemiBold
      font.features: { "tnum": 1 }
    }
  }

  Row {
    anchors.right: parent.right
    anchors.rightMargin: 14
    anchors.verticalCenter: parent.verticalCenter
    spacing: 5
    Text {
      text: pill.stats.temp > 0 ? "󰔄" : "󰘚"
      color: pill.stats.temp >= 80 ? pill.host.colorUrgent : pill.host.colorMuted
      font.family: pill.host.fontFamily
      font.pixelSize: 14
      Behavior on color { ColorAnimation { duration: 180 * pill.host.motionScale } }
    }
    Text {
      text: pill.stats.temp > 0 ? pill.stats.temp + "°" : pill.stats.memPercent + "%"
      color: pill.stats.temp >= 80 ? pill.host.colorUrgent : pill.host.ink
      font.family: "Adwaita Sans"
      font.pixelSize: 13
      font.weight: Font.DemiBold
      font.features: { "tnum": 1 }
      Behavior on color { ColorAnimation { duration: 180 * pill.host.motionScale } }
    }
  }
}
