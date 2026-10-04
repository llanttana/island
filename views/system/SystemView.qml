import QtQuick
import QtQuick.Layouts
import "../../components"

// The System page: live CPU, memory, and temperature, a short history of each,
// and the switch that keeps the monitor on the resting pill. Opened from the
// control center's CPU chip; the live activity can also open it.
ColumnLayout {
  id: system
  required property var host
  property bool active: false

  readonly property color text: host.colorText
  readonly property color textMuted: host.colorMuted
  readonly property color well: host.withAlpha(host.colorText, 0.1)
  readonly property int animDuration: host.motionBase
  readonly property var stats: host.systemStats

  spacing: 10
  onActiveChanged: if (active) Qt.callLater(function() { system.forceActiveFocus() })
  Keys.onEscapePressed: host.goBack()

  // One metric: glyph, name, value, and a thin level bar under it.
  component MetricRow: Item {
    id: metric
    property string icon: ""
    property string label: ""
    property string value: ""
    property real fraction: 0
    property color tint: system.host.colorAccent

    Layout.fillWidth: true
    implicitHeight: 54

    Text {
      id: metricGlyph
      anchors.left: parent.left
      anchors.leftMargin: 16
      anchors.verticalCenter: parent.verticalCenter
      text: metric.icon
      color: metric.tint
      font.family: system.host.fontFamily
      font.pixelSize: 17
    }
    Text {
      anchors.left: metricGlyph.right
      anchors.leftMargin: 12
      anchors.right: metricValue.left
      anchors.rightMargin: 12
      anchors.verticalCenter: parent.verticalCenter
      text: metric.label
      color: system.text
      font.family: "Adwaita Sans"
      font.pixelSize: 14
    }
    Text {
      id: metricValue
      anchors.right: parent.right
      anchors.rightMargin: 16
      anchors.verticalCenter: parent.verticalCenter
      text: metric.value
      color: system.text
      font.family: "Adwaita Sans"
      font.pixelSize: 14
      font.weight: Font.DemiBold
      font.features: { "tnum": 1 }
    }
    Rectangle {
      anchors.left: parent.left
      anchors.leftMargin: 16
      anchors.right: parent.right
      anchors.rightMargin: 16
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 10
      height: 4
      radius: 2
      color: system.well
      Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: parent.width * Math.max(0, Math.min(1, metric.fraction))
        radius: 2
        color: metric.tint
        Behavior on width { NumberAnimation { duration: system.host.motionPanel; easing.type: system.host.easeStandard } }
      }
    }
  }

  // A row of thin bars, newest on the right.
  component Spark: Item {
    id: spark
    property var values: []
    property real maxValue: 100
    property color tint: system.host.colorAccent

    Layout.fillWidth: true
    implicitHeight: 46

    Row {
      anchors.left: parent.left
      anchors.leftMargin: 16
      anchors.right: parent.right
      anchors.rightMargin: 16
      anchors.verticalCenter: parent.verticalCenter
      spacing: 2
      Repeater {
        model: spark.values
        delegate: Item {
          required property var modelData
          width: Math.max(1, (parent.width - (spark.values.length - 1) * 2) / Math.max(1, spark.values.length))
          height: spark.height
          Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: Math.max(1, parent.height * Math.min(1, Number(modelData) / spark.maxValue))
            radius: width / 2
            color: spark.tint
          }
        }
      }
    }
  }

  IslandNav {
    Layout.fillWidth: true
    host: system.host
    title: "System"
    onBack: system.host.view = "controls"
  }

  Flickable {
    id: scroller
    Layout.fillWidth: true
    Layout.preferredHeight: Math.min(groups.implicitHeight, 600)
    contentHeight: groups.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
      id: groups
      width: scroller.width
      spacing: 8

      IslandGroup {
        host: system.host
        title: "Now"

        MetricRow {
          icon: "󰍛"
          label: "CPU"
          value: Math.round(system.stats.cpu) + "%"
          fraction: system.stats.cpu / 100
          tint: system.host.colorAccent
        }
        MetricRow {
          icon: "󰘚"
          label: "Memory"
          value: system.formatBytes(system.stats.memUsed) + " / " + system.formatBytes(system.stats.memTotal)
          fraction: system.stats.memFraction
          tint: system.host.colorAccent
        }
        MetricRow {
          icon: "󰔄"
          label: "Temperature"
          value: system.stats.temp > 0 ? system.stats.temp + " °C" : "No sensor"
          fraction: system.stats.temp / 100
          tint: system.stats.temp >= 80 ? system.host.colorUrgent : system.host.colorAccent
        }
      }

      IslandGroup {
        host: system.host
        title: "Last two minutes"

        Spark { values: system.stats.cpuHistory; maxValue: 100; tint: system.host.colorText }
        Spark { values: system.stats.memHistory; maxValue: 100; tint: system.host.colorText }
        Spark { values: system.stats.tempHistory; maxValue: 100; tint: system.host.colorText }
      }

      IslandGroup {
        host: system.host
        title: "On the island"

        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: 56
          Column {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.right: pinSwitch.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text {
              text: "Keep the monitor visible"
              color: system.text
              font.family: "Adwaita Sans"
              font.pixelSize: 14
            }
            Text {
              text: "Show CPU and temperature on the resting pill, even when idle"
              color: system.textMuted
              font.family: "Adwaita Sans"
              font.pixelSize: 11
            }
          }
          IslandSwitch {
            id: pinSwitch
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            host: system.host
            checked: !!system.host.settings.systemMonitor
            onToggled: function(on) { system.host.settings.systemMonitor = on }
          }
        }
      }
    }
  }

  function formatBytes(bytes) {
    var value = Number(bytes) || 0
    if (value >= 1073741824) return (value / 1073741824).toFixed(1) + " GB"
    if (value >= 1048576) return Math.round(value / 1048576) + " MB"
    return Math.round(value / 1024) + " KB"
  }
}
