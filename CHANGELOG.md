# Changelog

All notable changes to Island are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Shelf: `Delete` takes the Ctrl+click selection off the shelf, or the tile the
  keyboard is on when nothing is selected.
- Shelf: double click opens a tile with `xdg-open`.
- The notification history limit is a setting rather than a hard-coded ten,
  with a **Clear** button next to it in Settings; the island reads and writes
  both through the companion's IPC.
- Island probes the `omarchy-*` helpers it uses at startup. On an older or
  trimmed Omarchy a feature whose helper is missing now hides itself -- the
  Record chip, the power buttons, the theme and wallpaper pickers, the Bluetooth
  controls -- instead of offering a control that quietly does nothing, and the
  timer notification falls back to `notify-send`.
- Tests for the companion setup scripts, covering the JSONC menu edit (empty,
  commented, trailing-comma, CRLF and already-present entries) and the backup
  rotation, plus a run of `install.sh` twice against a throwaway `HOME`.

### Changed

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

### Removed

- The user-arrangeable control-center tiles: arrange mode, drag-to-reorder,
  edge resize and the `tileOrder` / `tileWide` settings. The power profiles stay
  as one tabbed control.

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
