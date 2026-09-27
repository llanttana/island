import QtQuick

// iOS-style "now playing" wave: bars that bounce to random heights while
// `playing`, flanked by a small dot at each end. Shared by the media pill and
// the player view. The bars are stepped on the render loop, so they stay
// smooth at the display's refresh rate; the easing is time-based, so the
// motion looks the same at 60 Hz and at 120 Hz.
Row {
  id: wave
  property color color: "white"
  property bool playing: false
  property int bars: 5
  property real barWidth: 3
  property real maxHeight: 18

  spacing: barWidth

  Repeater {
    id: repeater
    model: wave.bars + 2
    delegate: Rectangle {
      required property int index
      readonly property bool dot: index === 0 || index === wave.bars + 1
      property real level: 0.3
      property real target: 0.3
      width: wave.barWidth
      height: dot ? wave.barWidth : wave.barWidth + (wave.maxHeight - wave.barWidth) * level
      radius: width / 2
      anchors.verticalCenter: parent.verticalCenter
      color: wave.color
      opacity: dot ? 0.8 : 1
    }
  }

  // The constants match the original 30 Hz timer: 0.45 of the remaining
  // distance per 33 ms step, retargeted every 5 steps (~165 ms).
  readonly property real easingTau: 33 / -Math.log(1 - 0.45)
  readonly property real retargetEvery: 165
  property double sinceRetarget: 0
  property double lastFrame: 0

  function step(dt) {
    if (dt <= 0) return
    dt = Math.min(dt, 100)
    sinceRetarget += dt
    var retarget = sinceRetarget >= retargetEvery
    if (retarget) sinceRetarget = 0
    var middle = (wave.bars + 1) / 2
    var k = 1 - Math.exp(-dt / easingTau)
    for (var i = 1; i <= wave.bars; i++) {
      var bar = repeater.itemAt(i)
      if (!bar) continue
      // The middle bars swing wider than the outer ones, like iOS's.
      var reach = 1 - Math.abs(i - middle) / middle * 0.45
      if (retarget) bar.target = (0.15 + Math.random() * 0.85) * reach
      bar.level += (bar.target - bar.level) * k
    }
  }

  FrameAnimation {
    running: wave.playing && wave.visible
    onRunningChanged: if (running) wave.lastFrame = 0
    onTriggered: {
      var now = Date.now()
      var dt = wave.lastFrame > 0 ? now - wave.lastFrame : 16.7
      wave.lastFrame = now
      wave.step(dt)
    }
  }
}
