import QtQuick
import Quickshell.Hyprland

// Workspace dots for the resting pill. The workspace set, the geometry, and
// switching live on the host (Island.qml) so the pill can size itself around
// them; this only draws them.
//
// One dot per workspace: dim while the workspace is empty, brighter once it has
// windows, and accent while it is focused. Clicking a dot switches to it.
Row {
  id: dots
  required property var host

  spacing: dots.host.workspaceDotGap

  Repeater {
    model: dots.host.workspaceIds
    delegate: Rectangle {
      required property int modelData

      readonly property var workspace: dots.host.workspaceById(modelData)
      readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
      readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

      width: dots.host.workspaceDotSize
      height: dots.host.workspaceDotSize
      radius: width / 2
      color: focused ? dots.host.colorAccent : dots.host.ink
      opacity: focused ? 1 : occupied ? 0.8 : 0.28
      scale: focused ? 1.35 : 1

      Behavior on opacity { NumberAnimation { duration: 150 * dots.host.motionScale; easing.type: Easing.OutCubic } }
      Behavior on color { ColorAnimation { duration: 150 * dots.host.motionScale } }
      Behavior on scale { NumberAnimation { duration: 200 * dots.host.motionScale; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: dots.host.focusWorkspace(modelData)
      }
    }
  }
}
