import QtQuick

// iOS-style switch: accent track when on, white knob sliding across. Shared by
// the island's settings and its Wi-Fi/Bluetooth pages.
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
    color: "#ffffff"
    Behavior on x { NumberAnimation { duration: 180 * sw.host.motionScale; easing.type: Easing.OutCubic } }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: sw.toggled(!sw.checked)
  }
}
