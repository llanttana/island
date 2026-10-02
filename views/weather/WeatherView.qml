import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../components"

// The Weather page: today at a glance and the next three days, fetched as one
// JSON document from wttr.in. The location is the one Omarchy already stores
// (the same file the control center's temperature chip reads).
ColumnLayout {
  id: weather
  required property var host
  property bool active: false

  readonly property color text: host.colorText
  readonly property color textMuted: host.colorMuted
  readonly property color well: host.withAlpha(host.colorText, 0.1)
  readonly property int animDuration: 180 * host.motionScale

  property string query: ""
  property var current: null
  property var days: []
  property string place: ""
  property string error: ""

  FileView {
    id: weatherLocation
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/weather.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        var d = JSON.parse(text())
        weather.query = (d.latitude !== undefined && d.longitude !== undefined)
          ? String(d.latitude) + "," + String(d.longitude)
          : String(d.name || "")
        if (d.name) weather.place = String(d.name)
      } catch (e) {
        weather.query = ""
      }
    }
    onFileChanged: reload()
  }

  Process {
    id: forecastRead
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: weather.apply(String(text || ""))
    }
  }

  function refresh() {
    if (weather.query === "" || forecastRead.running) return
    weather.error = ""
    forecastRead.command = ["curl", "-fsS", "--max-time", "12", "https://wttr.in/" + encodeURIComponent(weather.query) + "?format=j1"]
    forecastRead.running = true
  }

  function apply(raw) {
    try {
      var doc = JSON.parse(raw)
      var now = doc.current_condition && doc.current_condition.length ? doc.current_condition[0] : null
      weather.current = now
      weather.days = Array.isArray(doc.weather) ? doc.weather.slice(0, 3) : []
      if (doc.nearest_area && doc.nearest_area.length) {
        var area = doc.nearest_area[0]
        if (area.areaName && area.areaName.length) weather.place = String(area.areaName[0].value || weather.place)
      }
      if (!now) weather.error = "No weather data"
    } catch (e) {
      weather.error = "Could not read the forecast"
    }
  }

  function condition() {
    var now = weather.current
    if (!now || !now.weatherDesc || !now.weatherDesc.length) return ""
    return String(now.weatherDesc[0].value || "")
  }
  function iconFor(code, night) {
    code = Number(code)
    if (code === 113) return night ? "🌙" : "☀️"
    if (code === 116) return "⛅"
    if (code === 119 || code === 122) return "☁️"
    if (code === 143 || code === 248 || code === 260) return "🌫️"
    if ([200, 386, 389, 392, 395].indexOf(code) !== -1) return "⛈️"
    if ([179, 182, 185, 227, 230, 317, 320, 323, 326, 329, 332, 335, 338, 350, 362, 365, 368, 374, 377].indexOf(code) !== -1) return "❄️"
    return "🌧️"
  }
  function midday(day) {
    var hours = day && day.hourly ? day.hourly : []
    return hours.length > 4 ? hours[4] : (hours.length ? hours[hours.length - 1] : null)
  }
  function dayName(dateText) {
    var d = new Date(String(dateText) + "T12:00:00")
    var today = new Date()
    var sameDay = d.toDateString() === today.toDateString()
    return sameDay ? "Today" : Qt.formatDateTime(d, "ddd")
  }

  spacing: 10
  onActiveChanged: if (active) { Qt.callLater(function() { weather.forceActiveFocus() }); weather.refresh() }
  Keys.onEscapePressed: host.view = "controls"

  IslandNav {
    Layout.fillWidth: true
    host: weather.host
    title: "Weather"
    onBack: weather.host.view = "controls"

    Rectangle {
      width: 32
      height: 32
      radius: 16
      color: refreshMouse.containsMouse ? weather.host.withAlpha(weather.text, 0.16) : weather.well
      Behavior on color { ColorAnimation { duration: weather.animDuration } }
      Text {
        anchors.centerIn: parent
        text: "󰑐"
        color: weather.text
        font.family: weather.host.fontFamily
        font.pixelSize: 16
      }
      MouseArea {
        id: refreshMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: weather.refresh()
      }
    }
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
        host: weather.host
        title: weather.place !== "" ? weather.place : "Now"

        Text {
          Layout.fillWidth: true
          Layout.topMargin: 24
          Layout.bottomMargin: 24
          visible: weather.current === null
          horizontalAlignment: Text.AlignHCenter
          text: weather.error !== "" ? weather.error : "Loading the forecast…"
          color: weather.error !== "" ? weather.host.colorUrgent : weather.textMuted
          font.family: "Adwaita Sans"
          font.pixelSize: 12
        }

        RowLayout {
          Layout.fillWidth: true
          Layout.topMargin: 6
          Layout.bottomMargin: 6
          visible: weather.current !== null
          spacing: 16

          Text {
            Layout.leftMargin: 18
            text: weather.current ? weather.iconFor(weather.current.weatherCode, false) : ""
            font.pixelSize: 46
          }
          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text {
              text: weather.current ? weather.current.temp_C + "°" : ""
              color: weather.text
              font.family: "Adwaita Sans"
              font.pixelSize: 34
              font.weight: Font.DemiBold
              font.letterSpacing: -1
            }
            Text {
              Layout.fillWidth: true
              text: weather.condition()
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: weather.textMuted
              font.family: "Adwaita Sans"
              font.pixelSize: 12
            }
          }
        }

        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: 44
          Layout.bottomMargin: 6
          visible: weather.current !== null
          Row {
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            spacing: 18
            Text {
              text: "Feels like " + (weather.current ? weather.current.FeelsLikeC + "°" : "")
              color: weather.textMuted
              font.family: "Adwaita Sans"
              font.pixelSize: 11
            }
            Text {
              text: "Humidity " + (weather.current ? weather.current.humidity + "%" : "")
              color: weather.textMuted
              font.family: "Adwaita Sans"
              font.pixelSize: 11
            }
            Text {
              text: "Wind " + (weather.current ? weather.current.windspeedKmph + " km/h" : "")
              color: weather.textMuted
              font.family: "Adwaita Sans"
              font.pixelSize: 11
            }
          }
        }
      }

      IslandGroup {
        host: weather.host
        title: "Forecast"
        visible: weather.days.length > 0

        RowLayout {
          Layout.fillWidth: true
          Layout.margins: 8
          spacing: 6

          Repeater {
            model: weather.days
            delegate: Rectangle {
              id: dayCard
              required property var modelData
              readonly property var noon: weather.midday(modelData)

              Layout.fillWidth: true
              Layout.preferredHeight: 116
              radius: 14
              color: weather.host.withAlpha(weather.text, 0.05)

              Column {
                anchors.centerIn: parent
                spacing: 6
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: weather.dayName(dayCard.modelData.date)
                  color: weather.textMuted
                  font.family: "Adwaita Sans"
                  font.pixelSize: 11
                  font.weight: Font.DemiBold
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: weather.iconFor(dayCard.noon ? dayCard.noon.weatherCode : 113, false)
                  font.pixelSize: 30
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: dayCard.modelData.maxtempC + "°"
                  color: weather.text
                  font.family: "Adwaita Sans"
                  font.pixelSize: 16
                  font.weight: Font.DemiBold
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: dayCard.modelData.mintempC + "°"
                  color: weather.textMuted
                  font.family: "Adwaita Sans"
                  font.pixelSize: 12
                }
              }
            }
          }
        }
      }
    }
  }
}
