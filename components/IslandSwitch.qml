import QtQuick

// iOS-style switch: a filled track when on, with the knob sliding across. The
// knob is the track's ink, so the pair stays visible whatever the accent is
// (the accent is white on dark themes, where a white knob would vanish).
Rectangle {
  id: sw
  required property var host
  property bool checked: false
  signal toggled(bool checked)

  implicitWidth: 46
  implicitHeight: 28
  radius: 14
  opacity: enabled ? 1 : 0.4
  color: checked ? host.colorAccent : host.withAlpha(host.colorText, 0.1)
  Behavior on color { ColorAnimation { duration: 180 * sw.host.motionScale; easing.type: Easing.OutCubic } }

  Rectangle {
    width: 24
    height: 24
    radius: 12
    y: 2
    x: sw.checked ? sw.width - width - 2 : 2
    color: sw.checked ? sw.host.colorAccentText : "#ffffff"
    Behavior on color { ColorAnimation { duration: 180 * sw.host.motionScale; easing.type: Easing.OutCubic } }
    Behavior on x { NumberAnimation { duration: 180 * sw.host.motionScale; easing.type: Easing.OutCubic } }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: sw.toggled(!sw.checked)
  }
}
