import QtQuick
import "../components"
import "control-center"
import "power"
import "launcher"
import "themes"
import "wallpapers"
import "emoji"
import "keybinds"
import "clipboard"
import "menu"
import "player"
import "settings"
import "answer"
import "network"
import "bluetooth"
import "audio"
import "system"
import "calendar"
import "weather"
import "timer"
import "shelf"

// Every view the island can open. Each is a Surface: its name (also its IPC
// route: `omarchy-shell lanta.island show <name>`), how wide the
// island gets, its padding, and the view itself. Adding a view means adding
// its folder under views/ and one Surface here.
Item {
  id: views
  required property var host

  readonly property var surfaces: [controlsSurface, audioSurface, systemSurface, themesSurface, wallpapersSurface, appsSurface, powerSurface, emojiSurface, keybindsSurface, clipboardSurface, menuSurface, playerSurface, settingsSurface, answerSurface, wifiSurface, bluetoothSurface, calendarSurface, weatherSurface, timerSurface, shelfSurface]
  function surfaceFor(name) {
    for (var i = 0; i < surfaces.length; i++) if (surfaces[i].viewName === name) return surfaces[i]
    return null
  }

  Surface {
    id: controlsSurface
    host: views.host
    viewName: "controls"
    fixedWidth: 480
    maxHeight: 780
    ControlCenter { host: views.host; active: controlsSurface.active; anchors.fill: parent }
  }

  Surface {
    id: audioSurface
    host: views.host
    viewName: "audio"
    // Same width as the control center so a view switch only moves the pill
    // along one axis.
    fixedWidth: 480
    maxHeight: 720
    AudioView { host: views.host; active: audioSurface.active; anchors.fill: parent }
  }

  Surface {
    id: systemSurface
    host: views.host
    viewName: "system"
    fixedWidth: 480
    maxHeight: 720
    SystemView { host: views.host; active: systemSurface.active; anchors.fill: parent }
  }

  Surface {
    id: calendarSurface
    host: views.host
    viewName: "calendar"
    fixedWidth: 360
    CalendarView { host: views.host; active: calendarSurface.active; anchors.fill: parent }
  }

  Surface {
    id: weatherSurface
    host: views.host
    viewName: "weather"
    fixedWidth: 480
    maxHeight: 640
    WeatherView { host: views.host; active: weatherSurface.active; anchors.fill: parent }
  }

  Surface {
    id: timerSurface
    host: views.host
    viewName: "timer"
    fixedWidth: 480
    maxHeight: 560
    TimerView { host: views.host; active: timerSurface.active; anchors.fill: parent }
  }

  Surface {
    id: themesSurface
    host: views.host
    viewName: "themes"
    fixedWidth: 820
    padding: 20
    ThemeSwitcher { host: views.host; active: themesSurface.active; anchors.fill: parent }
  }

  Surface {
    id: wallpapersSurface
    host: views.host
    viewName: "wallpapers"
    fixedWidth: 820
    padding: 20
    WallpaperSwitcher { host: views.host; active: wallpapersSurface.active; anchors.fill: parent }
  }

  Surface {
    id: appsSurface
    host: views.host
    viewName: "apps"
    fixedWidth: 600
    AppLauncher { host: views.host; active: appsSurface.active; anchors.fill: parent }
  }

  Surface {
    id: emojiSurface
    host: views.host
    viewName: "emoji"
    fixedWidth: 600
    EmojiPicker { host: views.host; active: emojiSurface.active; anchors.fill: parent }
  }

  Surface {
    id: keybindsSurface
    host: views.host
    viewName: "keybinds"
    fixedWidth: 700
    KeybindList { host: views.host; active: keybindsSurface.active; anchors.fill: parent }
  }

  Surface {
    id: clipboardSurface
    host: views.host
    viewName: "clipboard"
    fixedWidth: 780
    ClipboardList { host: views.host; active: clipboardSurface.active; anchors.fill: parent }
  }

  Surface {
    id: menuSurface
    host: views.host
    viewName: "menu"
    fixedWidth: 520
    OmarchyMenu { host: views.host; active: menuSurface.active; anchors.fill: parent }
  }

  Surface {
    id: playerSurface
    host: views.host
    viewName: "player"
    fixedWidth: 440
    padding: 24
    PlayerView { host: views.host; active: playerSurface.active; anchors.fill: parent }
  }

  Surface {
    id: answerSurface
    host: views.host
    viewName: "answer"
    readonly property bool thinking: !!(view && view.thinking)
    fixedWidth: thinking ? 280 : 580
    padding: thinking ? 14 : 28
    AnswerView { host: views.host; active: answerSurface.active; anchors.fill: parent }
  }

  Surface {
    id: settingsSurface
    host: views.host
    viewName: "settings"
    fixedWidth: 540
    SettingsView { host: views.host; active: settingsSurface.active; anchors.fill: parent }
  }

  Surface {
    id: wifiSurface
    host: views.host
    viewName: "wifi"
    // Same width as the control center: switching between panel views
    // then moves the pill in one axis only, instead of sliding the outgoing
    // view sideways while it fades.
    fixedWidth: 480
    maxHeight: 720
    WifiView { host: views.host; active: wifiSurface.active; anchors.fill: parent }
  }

  Surface {
    id: bluetoothSurface
    host: views.host
    viewName: "bluetooth"
    // Same width as the control center: switching between panel views
    // then moves the pill in one axis only, instead of sliding the outgoing
    // view sideways while it fades.
    fixedWidth: 480
    maxHeight: 720
    BluetoothView { host: views.host; active: bluetoothSurface.active; anchors.fill: parent }
  }

  Surface {
    id: powerSurface
    host: views.host
    viewName: "power"
    padding: 18
    PowerMenu { host: views.host; active: powerSurface.active; anchors.fill: parent }
  }

  Surface {
    id: shelfSurface
    host: views.host
    viewName: "shelf"
    fixedWidth: 600
    maxHeight: 640
    ShelfView { host: views.host; active: shelfSurface.active; anchors.fill: parent }
  }
}
