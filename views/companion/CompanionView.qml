import QtQuick
import QtQuick.Layouts
import "../../components"

// What the first click on the setup pill opens: the sentence that says what
// setting the companion up actually does, and the two ways out of it.
//
// "Later" leaves the pill exactly as it was and does not ask again until the
// shell restarts: the island keeps that answer in a property, not in
// island.json, so a fresh shell asks again (Island.qml, companionSetupDismissed).
ColumnLayout {
  id: companionView
  required property var host
  property bool active: false

  spacing: 14

  Text {
    Layout.fillWidth: true
    text: "This switches Omarchy's notifications to Island's and restarts the shell."
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    color: companionView.host.colorText
    font.family: "Adwaita Sans"
    font.pixelSize: 14
  }

  RowLayout {
    Layout.alignment: Qt.AlignRight
    spacing: 8
    IslandButton {
      host: companionView.host
      label: "Set up"
      onClicked: companionView.host.installCompanion()
    }
    IslandButton {
      host: companionView.host
      label: "Later"
      onClicked: {
        companionView.host.companionSetupDismissed = true
        companionView.host.view = "rest"
      }
    }
  }
}
