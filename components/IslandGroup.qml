import QtQuick
import QtQuick.Layouts

// Titled inset card, iOS style: a small uppercase heading over a rounded panel
// that holds the rows. Rows are the default children.
ColumnLayout {
  id: group
  required property var host
  property string title: ""
  default property alias rows: body.data

  Layout.fillWidth: true
  spacing: 6

  Text {
    Layout.leftMargin: 16
    visible: group.title !== ""
    text: group.title.toUpperCase()
    color: group.host.colorMuted
    font.family: "Adwaita Sans"
    font.pixelSize: 11
    font.letterSpacing: 0.4
  }

  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: body.implicitHeight
    radius: 18
    color: group.host.withAlpha(group.host.colorText, 0.07)
    border.width: 1
    border.color: group.host.colorBorder

    ColumnLayout {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: 0
    }
  }
}
