import QtQuick

// A countdown timer shared by the control center chip, the Timer page, and the
// live activity on the resting pill. It keeps ticking while the island is
// closed; the page and the pill only read it.
Item {
  id: service

  property bool running: false
  property bool paused: false
  property int total: 0        // seconds the run started with
  property int remaining: 0    // seconds left
  property string label: "Timer"
  signal done(string label)

  readonly property real progress: service.total > 0
    ? Math.max(0, Math.min(1, (service.total - service.remaining) / service.total)) : 0

  function formatted() {
    var s = Math.max(0, service.remaining)
    var m = Math.floor(s / 60)
    var sec = s % 60
    return (m < 10 ? "0" : "") + m + ":" + (sec < 10 ? "0" : "") + sec
  }

  function start(seconds, label) {
    service.total = Math.max(1, Math.round(seconds))
    service.remaining = service.total
    service.label = String(label || "Timer")
    service.paused = false
    service.running = true
  }

  function stop() {
    service.running = false
    service.paused = false
    service.remaining = 0
  }

  function togglePause() {
    if (!service.running) return
    service.paused = !service.paused
  }

  function add(seconds) {
    if (!service.running) return
    service.remaining = Math.max(1, service.remaining + Math.round(seconds))
    service.total = Math.max(service.total, service.remaining)
  }

  Timer {
    interval: 1000
    repeat: true
    running: service.running && !service.paused
    onTriggered: {
      service.remaining--
      if (service.remaining > 0) return
      var finished = service.label
      service.running = false
      service.paused = false
      service.remaining = 0
      service.done(finished)
    }
  }
}
