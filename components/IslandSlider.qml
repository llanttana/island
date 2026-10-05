import QtQuick

// Horizontal level slider for the island's pages (per-application volume, screen
// colour temperature): a filled track with a knob, an optional leading glyph and
// a value label on the right. The vertical sliders in the control center fill
// from the foot; this one is the same idea turned on its side.
Item {
  id: slider
  required property var host
  property string icon: ""
  property real value: 0
  property string valueText: ""
  // Named by whoever places it: "Volume", "Brightness", and so on.
  property string accessibleName: ""

  Accessible.role: Accessible.Slider
  Accessible.name: accessibleName
  Accessible.value: Math.round(clamped * 100)
  Accessible.minimumValue: 0
  Accessible.maximumValue: 100
  signal moved(real value)

  implicitHeight: 34
  implicitWidth: 220
  opacity: enabled ? 1 : 0.4

  readonly property real clamped: Math.max(0, Math.min(1, Number(value) || 0))

  Text {
    id: iconText
    visible: slider.icon !== ""
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: visible ? 20 : 0
    text: slider.icon
    color: slider.host.colorMuted
    font.family: slider.host.fontFamily
    font.pixelSize: 15
  }

  Text {
    id: valueLabel
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    visible: slider.valueText !== ""
    text: slider.valueText
    color: slider.host.colorText
    font.family: "Adwaita Sans"
    font.pixelSize: 11
    font.weight: Font.DemiBold
    font.features: { "tnum": 1 }
    horizontalAlignment: Text.AlignRight
  }

  Rectangle {
    id: track
    anchors.left: iconText.right
    anchors.leftMargin: iconText.visible ? 8 : 0
    anchors.right: valueLabel.left
    anchors.rightMargin: valueLabel.visible ? 10 : 0
    anchors.verticalCenter: parent.verticalCenter
    height: 6
    radius: 3
    color: slider.host.withAlpha(slider.host.colorText, 0.14)

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: track.width * slider.clamped
      radius: track.radius
      color: slider.host.colorAccent
      Behavior on width {
        enabled: !sliderArea.pressed
        NumberAnimation { duration: slider.host.motionInstant; easing.type: slider.host.easeStandard }
      }
    }

    Rectangle {
      width: 14
      height: 14
      radius: 7
      anchors.verticalCenter: parent.verticalCenter
      x: Math.max(-7, Math.min(track.width - 7, track.width * slider.clamped - 7))
      color: slider.host.colorText
      border.width: 2
      border.color: slider.host.colorBackground
    }

    MouseArea {
      id: sliderArea
      anchors.fill: parent
      anchors.topMargin: -12
      anchors.bottomMargin: -12
      cursorShape: Qt.PointingHandCursor
      function apply(x) { slider.moved(Math.max(0, Math.min(1, x / width))) }
      onPressed: function(e) { apply(e.x) }
      onPositionChanged: function(e) { if (pressed) apply(e.x) }
    }
  }
}
