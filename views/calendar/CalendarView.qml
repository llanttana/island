import QtQuick
import QtQuick.Layouts
import "../../components"

// A month calendar, opened by clicking the resting pill's clock. The title is
// the visible month; the arrows move by a month and the dot returns to today.
ColumnLayout {
  id: calendar
  required property var host
  property bool active: false

  property int shownYear: new Date().getFullYear()
  property int shownMonth: new Date().getMonth()
  readonly property int cellHeight: 34
  readonly property int todayYear: new Date().getFullYear()
  readonly property int todayMonth: new Date().getMonth()
  readonly property int todayDay: new Date().getDate()

  readonly property color text: host.colorText
  readonly property color textMuted: host.colorMuted
  readonly property color well: host.withAlpha(host.colorText, 0.1)
  readonly property int animDuration: 180 * host.motionScale

  function daysInMonth(year, month) { return new Date(year, month + 1, 0).getDate() }
  // Monday-first: JS counts from Sunday.
  function firstWeekday(year, month) { return (new Date(year, month, 1).getDay() + 6) % 7 }
  function shiftMonth(delta) {
    var moved = new Date(shownYear, shownMonth + delta, 1)
    shownYear = moved.getFullYear()
    shownMonth = moved.getMonth()
  }
  function goToday() {
    shownYear = todayYear
    shownMonth = todayMonth
  }
  readonly property var cells: {
    var out = []
    var start = firstWeekday(shownYear, shownMonth)
    var count = daysInMonth(shownYear, shownMonth)
    for (var i = 0; i < 42; i++) {
      var day = i - start + 1
      out.push({ day: (day >= 1 && day <= count) ? day : 0 })
    }
    return out
  }

  spacing: 10
  onActiveChanged: if (active) Qt.callLater(function() { calendar.forceActiveFocus() })
  Keys.onEscapePressed: host.view = "rest"

  IslandNav {
    Layout.fillWidth: true
    host: calendar.host
    title: Qt.formatDateTime(new Date(calendar.shownYear, calendar.shownMonth, 1), "MMMM yyyy")
    onBack: calendar.host.view = "rest"

    Rectangle {
      width: 32
      height: 32
      radius: 16
      color: prevMonthMouse.containsMouse ? calendar.host.withAlpha(calendar.text, 0.16) : calendar.well
      Behavior on color { ColorAnimation { duration: calendar.animDuration } }
      Text {
        anchors.centerIn: parent
        text: "󰅁"
        color: calendar.text
        font.family: calendar.host.fontFamily
        font.pixelSize: 16
      }
      MouseArea {
        id: prevMonthMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: calendar.shiftMonth(-1)
      }
    }
    Rectangle {
      width: 32
      height: 32
      radius: 16
      color: todayMouse.containsMouse ? calendar.host.withAlpha(calendar.text, 0.16) : calendar.well
      Behavior on color { ColorAnimation { duration: calendar.animDuration } }
      Text {
        anchors.centerIn: parent
        text: "󰃭"
        color: calendar.text
        font.family: calendar.host.fontFamily
        font.pixelSize: 16
      }
      MouseArea {
        id: todayMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: calendar.goToday()
      }
    }
    Rectangle {
      width: 32
      height: 32
      radius: 16
      color: nextMonthMouse.containsMouse ? calendar.host.withAlpha(calendar.text, 0.16) : calendar.well
      Behavior on color { ColorAnimation { duration: calendar.animDuration } }
      Text {
        anchors.centerIn: parent
        text: "󰅂"
        color: calendar.text
        font.family: calendar.host.fontFamily
        font.pixelSize: 16
      }
      MouseArea {
        id: nextMonthMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: calendar.shiftMonth(1)
      }
    }
  }

  Item {
    Layout.fillWidth: true
    Layout.preferredHeight: calendar.cellHeight

    Row {
      id: weekdays
      anchors.fill: parent
      Repeater {
        model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
        delegate: Item {
          required property var modelData
          width: weekdays.width / 7
          height: weekdays.height
          Text {
            anchors.centerIn: parent
            text: modelData
            color: calendar.textMuted
            font.family: "Adwaita Sans"
            font.pixelSize: 11
            font.weight: Font.DemiBold
          }
        }
      }
    }
  }

  Item {
    Layout.fillWidth: true
    Layout.preferredHeight: calendar.cellHeight * 6

    Grid {
      id: grid
      anchors.fill: parent
      columns: 7
      Repeater {
        model: calendar.cells
        delegate: Item {
          required property var modelData
          readonly property bool isToday: modelData.day > 0
            && calendar.shownYear === calendar.todayYear
            && calendar.shownMonth === calendar.todayMonth
            && modelData.day === calendar.todayDay
          width: grid.width / 7
          height: calendar.cellHeight
          Rectangle {
            anchors.centerIn: parent
            width: 28
            height: 28
            radius: 14
            color: isToday ? calendar.host.colorAccent : "transparent"
            Text {
              anchors.centerIn: parent
              text: modelData.day > 0 ? modelData.day : ""
              color: isToday ? calendar.host.colorAccentText
                : modelData.day > 0 ? calendar.text : "transparent"
              font.family: "Adwaita Sans"
              font.pixelSize: 13
              font.weight: isToday ? Font.DemiBold : Font.Normal
              font.features: { "tnum": 1 }
            }
          }
        }
      }
    }
  }
}
