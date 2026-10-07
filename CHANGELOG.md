# Changelog

All notable changes to Island are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- A **Weather** switch in Settings. With it off the island makes no weather
  request at all -- the chip, the page and the fetch all stay away -- and an
  `island.json` without the key keeps reading as on.

### Changed
- The first click on the pill while the notifications companion is not set up
  asks before doing anything: what setting it up means, and **Set up** or
  **Later**. **Later** leaves the pill as it was and does not ask again until the
  shell restarts; a click used to install the companion and restart the shell on
  its own.

### Fixed
- With **System updates** switched off, a running package update is no longer
  shown on the resting pill: the setting used to apply only once the check it
  had started happened to finish.
- The launcher's **Ask** row is only offered when the CLI it would run is
  installed, and uses the other provider when the chosen one is missing: a
  machine without `claude` used to offer "Ask Claude" and then fail once the
  question was typed. **None** still means no Ask row at all.

## [0.5.0] - 2026-10-06

### Added

- Buttons, switches and sliders now carry `Accessible.name`, a role and their
  state, so a screen reader can say what a control is and whether it is on.
  The names come from the labels the user already sees.
- `tests/demo.sh`: prepares a scene for recording the demo video (backs up and
  clears the notification and clipboard history, writes a neutral file to drag)
  and fires the scripted events on a timeline while a person records. Nothing
  touches the user's configuration, everything it clears is backed up under
  `ISLAND_DEMO_DIR`, and `cleanup` -- also run when a run is interrupted -- puts
  it all back. `review` pulls a frame a second out of a finished recording and
  lists what to look for before publishing.
- `tests/smoke.sh`: restarts the shell and checks that the island actually came
  back -- layer, IPC, and no warnings in the journal -- because a plugin that
  fails to load only leaves one WARN line behind and a stock bar in its place.
- `tests/checks.sh` also fails on a file that declares `Component.onCompleted`
  twice, which qmllint accepts but QML does not.
- Shelf: `Delete` takes the Ctrl+click selection off the shelf, or the tile the
  keyboard is on when nothing is selected.
- Shelf: double click opens a tile with `xdg-open`.
- The notification history limit is a setting rather than a hard-coded ten,
  with a **Clear** button next to it in Settings; the island reads and writes
  both through the companion's IPC.
- The history list no longer imposes its own cap of ten entries: it shows
  everything the companion kept, which is what the limit above controls.
- Island probes the `omarchy-*` helpers it uses at startup. On an older or
  trimmed Omarchy a feature whose helper is missing now hides itself -- the
  Record chip, the power buttons, the theme and wallpaper pickers, the Bluetooth
  controls -- instead of offering a control that quietly does nothing, and the
  timer notification falls back to `notify-send`.
- `tests/checks.sh`, one command that runs everything which does not need an
  Omarchy session: bash syntax, shellcheck, the manifests as JSON, whitespace,
  `qmllint` over every QML file and the companion tests. Missing tools are
  skipped rather than fatal.
- Tests for the companion setup scripts, covering the JSONC menu edit (empty,
  commented, trailing-comma, CRLF and already-present entries) and the backup
  rotation, plus a run of `install.sh` twice against a throwaway `HOME`.

### Changed
- CI fetches the source as an archive instead of cloning it, so the repository's
  clone graph counts people rather than workflow runners.

- The notification history -- the read, the merge with the banners still on
  screen, and dismissing or clearing a row -- moved out of `Island.qml` into
  `components/NotificationHistory.qml`. `Island.qml` is down from 1520 to 1446
  lines.
- The notification companion's setup check and install moved out of
  `Island.qml` into `components/Companion.qml`, which owns the path, runs the
  check when it starts, and re-checks after an install.
- The control center's chip status reads (dictation, reminders, updates, active
  agent sessions) moved out of the panel into `components/OmarchyStatus.qml`, and
  its controls (power profiles, brightness, Game Mode) into
  `components/OmarchyControls.qml`. The panel keeps the same property names for
  both, so its body barely changed. The keyboard layout, the screen-recording
  state and the night light warmth followed them. `ControlCenter.qml` is down
  from 1677 to 1452 lines and is now layout, theme colours and the Quickshell
  service bindings.
- The companion setup only backs a config file up when it is actually about to
  change, and keeps the newest five copies instead of one per run.
- Weather is one shared service instead of two ad-hoc requests: Open-Meteo
  first, `wttr.in` as a fallback, the last answer cached on disk, and an
  offline state that keeps showing the last numbers instead of an error.
- Settings now opens like every other panel page: it shares the control center's
  width and height ceiling, so the island only changes height as the page
  arrives instead of widening from underneath it.
- Every animation takes its duration and easing from one set of motion tokens on
  the island root, so the whole plugin runs at a single tempo and easing family.
- `tests/checks.sh` calls a missing shellcheck out on its own WARN line and
  counts it in the summary, so a run that ends in "all checks passed" can no
  longer hide a linter that never ran; `ISLAND_REQUIRE_SHELLCHECK=1` turns the
  absence into a failure. CI runs shellcheck, so this is the pre-commit path,
  where the tool is not on `PATH`.

### Removed
- The clipboard, keybinding, app launcher, emoji and power screenshots are gone
  from the README: a clipboard view shows whatever was copied last, and the
  rest showed the reader little about the island itself.

- The user-arrangeable control-center tiles: arrange mode, drag-to-reorder,
  edge resize and the `tileOrder` / `tileWide` settings. The power profiles stay
  as one tabbed control.

### Fixed
- The theme and wallpaper pickers apply on one click again. A click only moved
  the selection, and the apply that was supposed to follow read the previous
  card, found it equal to the current one and closed the view instead.
- `tests/demo.sh` no longer restores a stale backup: a new scene replaces the
  snapshot it finds, so `cleanup` puts back the state you had when you prepared
  rather than one from an earlier run.

- The notification history rows draw their own near-opaque backing instead of
  the card's 7% tint. At 0.07 the window behind the panel decided the contrast
  of the row text — a white window washed the rows out to 2.6:1 — where the new
  colour holds about 5.6:1 over a white window and 6.0:1 over a black one, blur
  on or off. The card around the rows stays translucent.
- The age and the body line in a history row now clear 4.5:1 over a white or a
  black window too. At `textMuted` (0.62) and 0.72 they measured 3.19:1 and
  3.71:1 over white; both use a 0.9 ink on the row, which measures 4.84:1 and
  4.85:1 over white and 5.24:1 over black. The title keeps its full strength.
- The notification list no longer hides the entries past a fixed 190px window or
  cuts the last one in half: it reports its full height and lets the control
  center's own scroller move the panel, so everything the companion kept is
  reachable, and the card ends with a real bottom inset.
- `tests/demo.sh cleanup` no longer clears the notification history when there
  is nothing to restore. `companion clear` ran before the backup was looked for,
  so a bare `cleanup` — or an interrupted `run` whose `prepare` never happened —
  emptied the history with no copy to put back and reported only "nothing to
  restore". Cleanup now leaves the live state alone unless a scene was prepared,
  and `tests/demo.test.sh` pins the `prepare`/`run`/`cleanup` round trip by hash
  and the bare-cleanup case, with the shell's IPC stubbed and `HOME` thrown away.

## [0.4.0] - 2026-10-04

### Added

- Settings is split into tabs — Look, Pill, System and About — instead of one
  long scroll.
- A **Solid Black** island style: an opaque black pill with white ink, like the
  original design.
- **Keep Shelf**, which restores parked items after a shell restart.
- The power profiles (Power Saver, Balanced, Performance) as one tabbed control.
- User-arrangeable quick tiles: drag a tile to move it, drag its edge to resize,
  with an arrange mode and Save/Cancel.

### Changed

- Views are built lazily and the system monitor samples only while its page is
  open or pinned, which cuts idle memory and CPU use.

## [0.3.0] - 2026-10-04

### Added

- Shelf: multi-select with `Ctrl+click`, so a drag, copy or remove covers the
  whole selection.
- Shelf: a tile menu with Copy, Open, Remove, Clear and, for text, Save as .txt.
- Shelf: drag-out through [`ripdrag`](https://aur.archlinux.org/packages/ripdrag)
  for apps that refuse the island's own drag; the menu entry appears when
  ripdrag is installed.
- Shelf: dropping files, links and text straight onto the island.
- A bigger drop target: hovering the resting pill expands it into the shelf
  first.

### Changed

- Shelf tiles are smaller cards in a four-column grid, so more items fit.
- Every shelf item is drawn as a card, selected or not.
- The tile menu is tighter.

### Fixed

- `Esc` steps back through the view history instead of closing everything, and
  the shelf's own close button stays inside its tile.
- A row's own controls keep their clicks instead of the row swallowing them.

### Removed

- The shelf's keyboard hotkeys.

## [0.2.0] - 2026-10-03

### Added

- The shelf: park files, links and text on the island.

## [0.1.1] - 2026-10-02

### Added

- A preview image and a documented requirements list in the README.
- An MIT license declared in the manifest.

### Fixed

- The typed Wi-Fi password survives the list re-sorting.
- Notification clicks open the right app, including when the notification only
  carries a `.desktop` id.
- The notification banner closes after opening its app.
- The calendar follows midnight with the shell clock.
- The picker guards an unbuilt row and follows `currentKey` when it lands.
- The wttr.in location is URL-encoded, so locations with spaces work.

## 0.1.0 - 2026-09-26

First release. It predates tagged commits, so it has no comparison link.

### Added

- The island itself: a morphing pill with a clock, and album art with a sound
  wave while music plays.
- The control center, with Wi-Fi, Bluetooth, Focus and Game Mode tiles, output,
  input and volume sliders, device pills, the keyboard layout, screen recording,
  an idle inhibitor, night light with a warmth slider, the battery, weather, the
  timer and the power profile.
- Real Wi-Fi and Bluetooth pages that join, pair, connect and forget devices.
- An Audio page with output and input devices and per-application streams.
- A system monitor with a live two-minute graph, and a toggle to keep it on the
  pill.
- A weather page with a three-day forecast, and a calendar behind the clock.
- Timers with presets, a custom duration and a Pomodoro mode.
- Live activities for downloads, system updates, timers and the clipboard.
- Notification previews, and volume, mute and brightness on-screen displays
  drawn by the island.
- Ask AI: a launcher question answered by Claude Code or Codex CLI in the island.
- The player, app launcher, clipboard history, emoji and keybinding pickers, the
  theme and wallpaper switchers, the Omarchy menu and the power menu.
- Battery, workspace dots and auto-hide while a window is fullscreen.
- Frosted glass surfaces, accent colours taken from the current Omarchy theme,
  and a MacBook-style notch option.
- Settings for the island's own options, including animation speed.

[Unreleased]: https://github.com/llanttana/island/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/llanttana/island/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/llanttana/island/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/llanttana/island/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/llanttana/island/releases/tag/v0.1.1
