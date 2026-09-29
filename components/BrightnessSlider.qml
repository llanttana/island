import QtQuick
import Quickshell.Widgets

// The brightness counterpart of the volume pill: the island becomes a wide
// slider that fills with the accent from the left, sun glyph near the left end.
// Fed by omarchy-brightness-display, which the brightness keys notify (see the
// island's `brightnessHud`).
ClippingRectangle {
  id: slider
  required property var host
  // The island rectangle; the slider shares its corner radius.
  required property Item shape
  readonly property real level: Math.max(0, Math.min(1, host.brightnessLevel))
  // Animate the level, not the pixel width, so the fill doesn't restart its
  // motion every frame while the island morphs.
  property real shownLevel: level
  Behavior on shownLevel { NumberAnimation { duration: 220 * host.motionScale; easing.type: Easing.OutCubic } }
  radius: shape.radius
  color: "transparent"
  opacity: host.brightnessPill ? 1 : 0
  visible: opacity > 0.01
  Behavior on opacity { NumberAnimation { duration: opacity > 0.5 ? 70 : 150 * host.motionScale; easing.type: Easing.InOutQuad } }

  // Grey track behind the fill: solid, since the clipping shape drops
  // translucent colors.
  Rectangle {
    anchors.fill: parent
    color: "#2a2a2a"
  }
  Rectangle {
    id: brightnessFill
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: parent.width * slider.shownLevel
    color: host.colorAccent
  }
  Text {
    anchors.left: parent.left
    anchors.leftMargin: 18
    anchors.verticalCenter: parent.verticalCenter
    // Accent ink on the fill, light text when the fill doesn't reach it.
    readonly property bool onFill: brightnessFill.width > x + width / 2
    text: slider.level <= 0.25 ? "󰃞" : slider.level <= 0.6 ? "󰃟" : "󰃠"
    color: onFill ? host.colorAccentText : host.colorText
    font.family: host.fontFamily
    font.pixelSize: 26
    Behavior on color { ColorAnimation { duration: 120 * host.motionScale } }
  }
}
