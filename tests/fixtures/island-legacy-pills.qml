// Frozen reference: the island's pill rules, cut out of the live sources while
// they still held the boolean chain, so that tests/pill-legacy.test.js stops
// reading the sources. After stage 2 moves the sources onto the model these
// lines change by design; this freeze is what keeps the reference honest.
//
// Each block starts with "== <file>:<first line>" and holds the source lines
// verbatim, one per comment line -- including their indentation. The test joins
// a block's continuation lines (the ones that start with &&, ||, ? or :) the
// same way the QML parses them, and checks the result against the formulas it
// knows. "node tests/pill-legacy.test.js --verify-live" cuts the same lines out
// of the live files instead and reports the first difference, block by block;
// that comparison is a one-off, because the freeze is the point.
//
// Cut at 74f43afe7e8e6d87: the sha256 of the legacy booleans and pill box over
// 6 settings x 6 companion statuses x 2^9 raw flags = 18432 states.
//
// The body is a QML comment inside a real root object on purpose: the file
// lives under tests/fixtures, and tests/checks.sh lints every tracked *.qml,
// where a bare fragment would be reported as a syntax error.

import QtQuick

QtObject {
  // == Island.qml:37
  //   readonly property bool mediaPill: view === "rest" && mediaPlaying && !companionNeedsSetup && settings.mediaPill && !downloadPill && !systemPill && !timerPill
  // == Island.qml:64
  //   readonly property bool systemPinned: !!settings.systemMonitor
  // == Island.qml:65
  //   readonly property bool systemHot: !!settings.autoMonitorHot && systemSampler.ready && (systemSampler.temp >= 85 || systemSampler.cpu >= 95)
  // == Island.qml:66
  //   readonly property bool systemPill: view === "rest" && !companionNeedsSetup && systemSampler.ready && !timerPill
  //     && (systemPinned || systemHot)
  // == Island.qml:73
  //   readonly property bool timerPill: view === "rest" && !companionNeedsSetup && timerService.running
  // == Island.qml:74
  //   readonly property bool downloadDone: view === "rest" && !companionNeedsSetup
  //     && (downloadTracker.finishedName !== "" || packageTracker.finishedTitle !== "")
  // == Island.qml:76
  //   readonly property bool downloadActive: view === "rest" && !companionNeedsSetup
  //     && (downloadTracker.active || packageTracker.active) && !downloadDone
  // == Island.qml:78
  //   readonly property bool downloadPill: downloadDone || downloadActive
  // == Island.qml:426
  //   readonly property real clockSlot: settings.clockSeconds ? 86 : 56
  // == Island.qml:429
  //   readonly property bool pillHidden: (barHidden || (settings.hideFullscreen && outputFullscreen && !companionNeedsSetup)) && view === "rest"
  // == Island.qml:494
  //   readonly property real restWidth: {
  //     if (!accessoriesShown) return 100
  //     var width = 24 + clockSlot
  //     if (workspaceDotsShown) width += workspaceDotsWidth + 10
  //     if (batteryBadgeShown) width += batteryBadgeWidth + 10
  //     return Math.max(100, Math.round(width))
  // == Island.qml:1137
  //           readonly property real targetWidth: activeSurface ? activeSurface.islandWidth
  //             : root.notificationPill ? 440
  //             : root.volumePill ? 240
  //             : root.brightnessPill ? 240
  //             : root.clipboardPill ? 320
  //             : root.view === "feedback" ? 330
  //             : root.companionNeedsSetup ? 250
  //             : root.downloadDone ? 360
  //             : root.downloadActive ? (root.downloadTracker.active ? 240 : 280)
  //             : root.timerPill ? 240
  //             : root.systemPill ? 240
  //             : root.mediaPill ? 240
  //             : root.dropActive ? 360
  //             : root.restWidth
  // == Island.qml:1151
  //           readonly property real targetHeight: activeSurface ? activeSurface.islandHeight
  //             : root.notificationPill ? 84
  //             : root.clipboardPill ? (root.settings.notch ? 40 : 44)
  //             : root.downloadDone ? 64
  //             : root.mediaPill || root.downloadPill || root.systemPill || root.timerPill ? (root.settings.notch ? 40 : 44)
  //             : root.volumePill ? 56
  //             : root.brightnessPill ? 56
  //             : root.dropActive ? 64
  //             : root.view === "rest" ? (root.settings.notch ? 36 : 40) : 52
  // == components/Companion.qml:17
  //   readonly property bool needsSetup: status !== "" && status !== "ok"
  // == companion/check.sh:3
  // #   ok           installed, identical to this repo's copy, and enabled
  // #   missing      not installed in ~/.config/omarchy/plugins
  // #   outdated     installed but differs from this repo's copy
  // #   not-enabled  installed, but shell.json doesn't load it (or still loads
  // #                the stock omarchy.notifications alongside it)
  // #   menu         the Omarchy menu's Theme, Background, Apps, System, Emoji, or Keybindings entry
}
