import QtQuick

// Page navigation bar shared by the island's sub-pages: a round back button,
// a centred title, and room for controls on the right (see `trailing`).
Item {
  id: nav
  required property var host
  property string title: ""
  default property alias trailing: slot.data
  // Optional controls on the leading side, next to the back button (the
  // calendar's "previous month", for instance).
  property alias leading: leadingSlot.data
  signal back()

  implicitHeight: 36

  Rectangle {
    id: backButton
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: 32
    height: 32
    radius: 16
    color: backMouse.containsMouse ? nav.host.withAlpha(nav.host.colorText, 0.16) : nav.host.withAlpha(nav.host.colorText, 0.1)
    Behavior on color { ColorAnimation { duration: 180 * nav.host.motionScale } }
    Text {
      anchors.centerIn: parent
      text: "󰅁"
      color: nav.host.colorText
      font.family: nav.host.fontFamily
      font.pixelSize: 18
    }
    MouseArea {
      id: backMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: nav.back()
    }
  }

  Text {
    anchors.centerIn: parent
    text: nav.title
    color: nav.host.colorText
    font.family: "Adwaita Sans"
    font.pixelSize: 16
    font.weight: Font.DemiBold
    font.letterSpacing: -0.3
  }

  Row {
    id: leadingSlot
    anchors.left: parent.left
    anchors.leftMargin: 40
    anchors.verticalCenter: parent.verticalCenter
    spacing: 8
  }

  Row {
    id: slot
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: 8
  }
}
