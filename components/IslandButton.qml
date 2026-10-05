import QtQuick

// Small capsule button used by the island's list pages (Join, Disconnect,
// Forget, …).
Rectangle {
  id: button
  required property var host
  property string label: ""
  property bool danger: false

  // Screen readers get the label the user already sees.
  Accessible.role: Accessible.Button
  Accessible.name: label
  signal clicked()

  implicitWidth: buttonLabel.implicitWidth + 26
  implicitHeight: 34
  radius: 17
  color: button.danger ? host.withAlpha(host.colorUrgent, 0.18)
    : buttonMouse.containsMouse ? host.withAlpha(host.colorText, 0.16)
    : host.withAlpha(host.colorText, 0.1)
  Behavior on color { ColorAnimation { duration: button.host.motionBase; easing.type: button.host.easeStandard } }

  Text {
    id: buttonLabel
    anchors.centerIn: parent
    text: button.label
    color: button.danger ? button.host.colorUrgent : button.host.colorText
    font.family: "Adwaita Sans"
    font.pixelSize: 13
    font.weight: Font.Medium
  }

  MouseArea {
    id: buttonMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: button.clicked()
  }
}
