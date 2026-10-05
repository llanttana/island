import QtQuick
import QtQuick.Layouts
import "../../components"

// The Weather page: today at a glance and the next three days. The numbers come
// from the island's shared weather service (components/Weather.qml), which owns
// the location, the Open-Meteo request, the on-disk cache and the offline state
// -- the same service behind the control center's temperature chip.
ColumnLayout {
  id: weather
  required property var host
  property bool active: false

  readonly property color text: host.colorText
  readonly property color textMuted: host.colorMuted
  readonly property color well: host.withAlpha(host.colorText, 0.1)
  readonly property int animDuration: host.motionBase

  readonly property var service: host.weather

  // What to say when there is nothing to show yet, or nothing to show at all.
  readonly property string statusText: {
    if (service.current) return ""
    if (service.state === "nolocation") return "Omarchy has no location saved"
    if (service.state === "offline") return "No network, and nothing cached yet"
    return "Loading the forecast…"
  }
  function dayName(dateText) { return service.dayName(dateText) }
  function iconFor(code, night) { return service.iconFor(code, night) }
  function condition(code) { return service.condition(code) }

  spacing: 10
  onActiveChanged: if (active) { Qt.callLater(function() { weather.forceActiveFocus() }); weather.service.refresh() }
  Keys.onEscapePressed: host.goBack()

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
      Behavior on color { ColorAnimation { duration: weather.animDuration; easing.type: weather.host.easeStandard } }
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
        onClicked: weather.service.refresh(true)
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
        title: weather.service.place !== "" ? weather.service.place : "Now"

        Text {
          Layout.fillWidth: true
          Layout.topMargin: 24
          Layout.bottomMargin: 24
          visible: !weather.service.current
          horizontalAlignment: Text.AlignHCenter
          text: weather.statusText
          color: weather.service.state === "offline" || weather.service.state === "nolocation"
            ? weather.host.colorUrgent : weather.textMuted
          font.family: "Adwaita Sans"
          font.pixelSize: 12
        }

        RowLayout {
          Layout.fillWidth: true
          Layout.topMargin: 6
          Layout.bottomMargin: 6
          visible: !!weather.service.current
          spacing: 16

          Text {
            Layout.leftMargin: 18
            text: weather.service.current
              ? weather.iconFor(weather.service.current.code, !weather.service.current.isDay) : ""
            font.pixelSize: 46
          }
          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text {
              text: weather.service.current ? weather.service.current.tempC + "°" : ""
              color: weather.text
              font.family: "Adwaita Sans"
              font.pixelSize: 34
              font.weight: Font.DemiBold
              font.letterSpacing: -1
            }
            Text {
              Layout.fillWidth: true
              text: weather.service.current ? weather.condition(weather.service.current.code) : ""
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
          visible: !!weather.service.current
          Row {
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            spacing: 18
            Text {
              text: "Feels like " + (weather.service.current ? weather.service.current.feelsC + "°" : "")
              color: weather.textMuted
              font.family: "Adwaita Sans"
              font.pixelSize: 11
            }
            Text {
              text: "Humidity " + (weather.service.current ? weather.service.current.humidity + "%" : "")
              color: weather.textMuted
              font.family: "Adwaita Sans"
              font.pixelSize: 11
            }
            Text {
              text: "Wind " + (weather.service.current ? weather.service.current.windKmh + " km/h" : "")
              color: weather.textMuted
              font.family: "Adwaita Sans"
              font.pixelSize: 11
            }
            Text {
              visible: weather.service.stale
              text: "Offline · last seen " + Qt.formatDateTime(new Date(weather.service.fetchedAt), "HH:mm")
              color: weather.host.colorUrgent
              font.family: "Adwaita Sans"
              font.pixelSize: 11
            }
          }
        }
      }

      IslandGroup {
        host: weather.host
        title: "Forecast"
        visible: weather.service.days.length > 0

        RowLayout {
          Layout.fillWidth: true
          Layout.margins: 8
          spacing: 6

          Repeater {
            model: weather.service.days
            delegate: Rectangle {
              id: dayCard
              required property var modelData

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
                  text: weather.iconFor(dayCard.modelData.code, false)
                  font.pixelSize: 30
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: dayCard.modelData.maxC + "°"
                  color: weather.text
                  font.family: "Adwaita Sans"
                  font.pixelSize: 16
                  font.weight: Font.DemiBold
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: dayCard.modelData.minC + "°"
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
