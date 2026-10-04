import QtQuick

// Battery readout for the resting pill. The reading lives on the host
// (Island.qml); this only draws the charge glyph and the percentage.
Row {
  id: badge
  required property var host

  spacing: 3

  Text {
    anchors.verticalCenter: parent.verticalCenter
    text: badge.host.batteryIcon()
    color: badge.host.batteryTint
    font.family: badge.host.fontFamily
    font.pixelSize: 13
    Behavior on color { ColorAnimation { duration: badge.host.motionBase; easing.type: badge.host.easeStandard } }
  }

  Text {
    anchors.verticalCenter: parent.verticalCenter
    text: badge.host.batteryPercent + "%"
    color: badge.host.batteryTint
    font.family: "Adwaita Sans"
    font.pixelSize: 12
    font.weight: Font.DemiBold
    font.features: { "tnum": 1 }
    font.letterSpacing: -0.2
    Behavior on color { ColorAnimation { duration: badge.host.motionBase; easing.type: badge.host.easeStandard } }
  }
}
