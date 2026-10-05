#!/bin/bash
# Prepare the scene for a demo recording of the island, and fire the few events
# that have to land on a timeline while a person records.
#
#   tests/demo.sh prepare   back up the history, clear the scene, print a checklist
#   tests/demo.sh run       count down, then fire the timed events
#   tests/demo.sh cleanup   put everything back (also runs when a run is interrupted)
#   tests/demo.sh status    what is prepared right now
#   tests/demo.sh review F  pull a frame a second out of a recording, with advice
#
# The recording itself is started and stopped by hand: only a person can frame
# the shot. This script never touches a recorder.
#
# Nothing here writes to the user's configuration. Every path it clears is
# copied under $ISLAND_DEMO_DIR first, and everything it creates lives there too.
#
# The default is under the state directory, not /tmp: the backup is the user's
# notification and clipboard history, and a reboot or a dead session between
# prepare and cleanup would take /tmp with it and leave that history gone for
# good. Set ISLAND_DEMO_DIR to override it -- tests do, to keep their fixtures
# out of the state directory.
set -euo pipefail

# ---------------------------------------------------------------------------
# The timeline, in seconds from the moment the countdown starts.
readonly COUNTDOWN=5          # the person starts recording during this
readonly NOTIFY_AT=7          # first notification
readonly TIMER_AT=11          # countdown on the island's pill
readonly TIMER_SECONDS=10
readonly NOTIFY_AGAIN_AT=15   # a second notification, if the first was missed
# ---------------------------------------------------------------------------

demo_dir=${ISLAND_DEMO_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/island-demo}
readonly demo_dir
readonly backup_dir="$demo_dir/backup"
readonly files_dir="$demo_dir/files"
readonly marker="$demo_dir/.prepared"

readonly state_dir="$HOME/.local/state/omarchy"
readonly notif_history="$state_dir/notifications/history"
readonly clip_history="$state_dir/clipboard-history.json"
readonly shelf_file="$state_dir/island-shelf.json"
readonly dnd_state="$demo_dir/.dnd-before"

say()  { printf '%s\n' "$*"; }
head2() { printf '\n== %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

# The island's IPC is the only thing here that may be missing: everything else
# is files. A missing island is worth saying out loud rather than half-running.
island_up() { timeout 5 omarchy-shell lanta.island toggle >/dev/null 2>&1; }

island() {
  timeout 10 omarchy-shell lanta.island "$@" >/dev/null 2>&1 || warn "island did not answer: $*"
}

companion() {
  timeout 10 omarchy-shell notifications "$@" >/dev/null 2>&1 || warn "companion did not answer: $*"
}

# ---------------------------------------------------------------------------
# Backups
#
# A backup is taken once. Running prepare twice must not replace a good backup
# with the already-cleared state, so an existing copy is left alone.

copy_once() {
  local src=$1 dest=$2
  if [ -e "$dest" ]; then
    say "   already backed up: $(basename "$dest")"
    return 0
  fi
  cp -a -- "$src" "$dest"
  say "   backed up: $(basename "$dest")"
}

backup_all() {
  mkdir -p "$backup_dir"
  head2 "Backing up"
  [ -d "$notif_history" ] && copy_once "$notif_history" "$backup_dir/notifications-history"
  [ -f "$clip_history" ] && copy_once "$clip_history" "$backup_dir/clipboard-history.json"
  [ -f "$shelf_file" ] && copy_once "$shelf_file" "$backup_dir/island-shelf.json"
  if [ ! -f "$dnd_state" ]; then
    timeout 10 omarchy-shell notifications dndState >"$dnd_state" 2>/dev/null || echo "off" >"$dnd_state"
    say "   backed up: focus state ($(cat "$dnd_state"))"
  fi
  return 0
}

# How old the backup is, in words. A backup sitting in the state directory can
# outlive the session that made it, and an old one is worth noticing: whatever
# was copied after it was taken is not in it, and cleanup would restore that
# older state over the newer history.
backup_age() {
  local f=$1 now mtime d
  [ -e "$f" ] || return 0
  now=$(date +%s)
  mtime=$(stat -c %Y "$f" 2>/dev/null || echo "$now")
  d=$((now - mtime))
  if [ "$d" -lt 3600 ]; then printf '%d min' "$((d / 60))"
  elif [ "$d" -lt 86400 ]; then printf '%d h' "$((d / 3600))"
  else printf '%d d' "$((d / 86400))"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# The neutral file
#
# A one-page PDF written by hand: no metadata, a neutral name, and nothing that
# needs a tool to generate. Offsets are computed as it is built, so it is a
# valid file rather than something that only looks like one.

make_pdf() {
  local out=$1 content obj1 obj2 obj3 o1 o2 o3 ox
  obj1='1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj'
  obj2='2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj'
  obj3='3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj'
  content='%PDF-1.4
'
  o1=${#content}; content+="$obj1
"
  o2=${#content}; content+="$obj2
"
  o3=${#content}; content+="$obj3
"
  ox=${#content}
  # Every xref entry is exactly 20 bytes, which is why each one ends in a space
  # before the newline. The space lives in $pad so the source lines themselves do
  # not end in whitespace, which git --check rightly complains about.
  local pad=' '
  content+="xref
0 4
0000000000 65535 f$pad
$(printf '%010d' "$o1") 00000 n$pad
$(printf '%010d' "$o2") 00000 n$pad
$(printf '%010d' "$o3") 00000 n$pad
trailer<</Size 4/Root 1 0 R>>
startxref
$ox
%%EOF
"
  printf '%s' "$content" >"$out"
}

# A plain gradient: neutral, no metadata, no personal detail, and it shows as a
# picture on the shelf rather than as a document icon.
make_image() {
  local out=$1
  ffmpeg -v error -y -f lavfi \
    -i "gradients=s=1280x720:c0=0x1b2a41:c1=0x7fb2d9:c2=0xd8e6f2:n=3:x0=0:y0=0:x1=1280:y1=720" \
    -frames:v 1 "$out"
}

demo_file() {
  local p
  for p in "$files_dir/demo-shot.png" "$files_dir/demo-report.pdf"; do
    if [ -f "$p" ]; then printf '%s' "$p"; return 0; fi
  done
  return 0
}

make_files() {
  head2 "The file to drag onto the island"
  mkdir -p "$files_dir"
  local existing
  existing=$(demo_file)
  if [ -n "$existing" ]; then
    say "   already there: $existing"
    return 0
  fi
  if command -v ffmpeg >/dev/null 2>&1 && make_image "$files_dir/demo-shot.png" 2>/dev/null \
     && [ -s "$files_dir/demo-shot.png" ]; then
    say "   wrote $files_dir/demo-shot.png"
    return 0
  fi
  rm -f -- "$files_dir/demo-shot.png"
  make_pdf "$files_dir/demo-report.pdf"
  say "   ffmpeg is not installed, so this is a plain PDF instead:"
  say "   $files_dir/demo-report.pdf"
}

# ---------------------------------------------------------------------------

clear_history() {
  head2 "Clearing the scene"
  mkdir -p "$notif_history"
  find "$notif_history" -mindepth 1 -delete 2>/dev/null || true
  say "   notification history emptied"
  companion dismissAll
  printf '[]\n' >"$clip_history"
  say "   clipboard history emptied"
  island shelfClear
  say "   shelf emptied"
  companion setDnd false
  say "   focus (do not disturb) off"
  island timerStop
  say "   timer reset"
}

checklist() {
  cat <<'LIST'

== Before you hit record

   [ ] quit mail, chat and anything that pops up on its own
   [ ] a neutral wallpaper: the default one, not your own photo
   [ ] windows that show a hostname, a username or a path are closed
       -- the terminal is the usual culprit
   [ ] do not open the Wi-Fi page on camera: it lists the neighbours' networks
   [ ] check the island's own settings pane is on a tab you are happy to show

== While recording

   * start the recorder by hand during the countdown; this script does not
   * everything that is not on the timeline below is yours to do:
     clicking through views, dragging the file onto the shelf, Ask AI,
     switching theme or wallpaper
LIST
}

cmd_prepare() {
  command -v omarchy-shell >/dev/null || die "omarchy-shell is not on PATH; is this an Omarchy session?"
  if [ -f "$marker" ]; then
    warn "the scene is already prepared; keeping the existing backup and clearing again"
  elif [ -e "$backup_dir/clipboard-history.json" ]; then
    warn "an older backup is here (taken $(backup_age "$backup_dir/clipboard-history.json") ago)."
    warn "Reusing it, so anything copied since then will be missing from the history"
    warn "that cleanup restores. Remove $backup_dir to start a fresh one."
  fi
  mkdir -p "$demo_dir"
  backup_all
  make_files
  clear_history
  : >"$marker"
  say ""
  say "scene ready. The file to drag is: $(demo_file)"
  say "next: tests/demo.sh run     (start the recorder during the countdown)"
  checklist
}

# ---------------------------------------------------------------------------

wait_until() {
  local target=$1 now
  while :; do
    now=$(date +%s)
    if [ "$((now - demo_start))" -ge "$target" ]; then break; fi
    sleep 0.2
  done
}

cmd_run() {
  command -v omarchy-shell >/dev/null || die "omarchy-shell is not on PATH; is this an Omarchy session?"
  [ -f "$marker" ] || warn "the scene was not prepared; run prepare first for a clean history"

  head2 "Timeline"
  say "   T+${NOTIFY_AT}s   first notification"
  say "   T+${TIMER_AT}s   a ${TIMER_SECONDS}s timer on the pill"
  say "   T+${NOTIFY_AGAIN_AT}s   second notification, in case the first was missed"
  say "   the rest is yours"

  # An interrupted run puts everything back: nothing more will be recorded, so
  # there is no reason to leave the history cleared. A run that finishes leaves
  # the scene alone, because the person is still recording around it.
  run_finished=false
  trap 'if [ "$run_finished" != true ]; then printf "\n"; cmd_cleanup; fi' EXIT
  # HUP as well: closing the terminal that runs this is the common way to lose
  # a run, and it must put the history back like any other interruption.
  trap 'printf "\ninterrupted\n"; exit 130' INT TERM HUP

  demo_start=$(date +%s)
  printf '\n'
  local i
  for ((i = COUNTDOWN; i > 0; i--)); do
    printf '\r   start recording... %d ' "$i"
    sleep 1
  done
  printf '\r   recording                            \n\n'

  wait_until "$NOTIFY_AT"
  say "   T+${NOTIFY_AT}s  notification"
  timeout 10 omarchy-notification-send "Build finished" "All tests passed" >/dev/null 2>&1 \
    || warn "could not send the notification"

  wait_until "$TIMER_AT"
  say "   T+${TIMER_AT}s  timer ${TIMER_SECONDS}s"
  island timer "$TIMER_SECONDS" "Demo"

  wait_until "$NOTIFY_AGAIN_AT"
  say "   T+${NOTIFY_AGAIN_AT}s  second notification"
  timeout 10 omarchy-notification-send "Build finished" "All tests passed" >/dev/null 2>&1 \
    || warn "could not send the notification"

  run_finished=true
  trap - EXIT INT TERM
  say ""
  say "the scripted part is done; keep recording as long as you like."
  say "when you stop: tests/demo.sh cleanup"
}

# ---------------------------------------------------------------------------

cmd_cleanup() {
  local restored=0

  # Notifications still on screen are archived the moment they are dismissed, so
  # they have to go before the history is put back -- otherwise they land in it
  # a second later and the restored state is no longer the one that was saved.
  companion dismissAll
  sleep 1
  companion clear

  if [ -d "$backup_dir/notifications-history" ]; then
    rm -rf -- "$notif_history"
    mkdir -p "$(dirname "$notif_history")"
    cp -a -- "$backup_dir/notifications-history" "$notif_history"
    say "   notification history restored"
    restored=1
  fi
  if [ -f "$backup_dir/clipboard-history.json" ]; then
    cp -a -- "$backup_dir/clipboard-history.json" "$clip_history"
    say "   clipboard history restored"
    restored=1
  fi
  if [ -f "$backup_dir/island-shelf.json" ]; then
    cp -a -- "$backup_dir/island-shelf.json" "$shelf_file"
    say "   shelf restored"
    restored=1
  fi
  if [ -f "$dnd_state" ]; then
    local before
    before=$(cat "$dnd_state")
    if [ "$before" = "on" ]; then companion setDnd true; else companion setDnd false; fi
    say "   focus state restored ($before)"
    restored=1
  fi

  island timerStop
  rm -rf -- "$files_dir"
  rm -f -- "$marker"

  if [ "$restored" -eq 0 ]; then
    say "nothing to restore (the scene was not prepared)"
  else
    say "cleaned up. The backup stays in $backup_dir until you remove it."
  fi
  return 0
}

# ---------------------------------------------------------------------------

cmd_status() {
  say "demo directory: $demo_dir"
  if [ -f "$marker" ]; then
    say "scene:          prepared"
  else
    say "scene:          not prepared"
  fi
  if [ -d "$backup_dir" ]; then
    local age=""
    if [ -e "$backup_dir/clipboard-history.json" ]; then
      age=" ($(backup_age "$backup_dir/clipboard-history.json") old)"
    fi
    say "backup:         $(find "$backup_dir" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ') item(s) in $backup_dir$age"
    find "$backup_dir" -mindepth 1 -maxdepth 1 -printf '                  %f\n' 2>/dev/null || true
  else
    say "backup:         none"
  fi
  local file
  file=$(demo_file)
  if [ -n "$file" ]; then
    say "demo file:      $file"
  else
    say "demo file:      none"
  fi
  if island_up; then say "island:         answering"; else say "island:         not answering"; fi
  return 0
}

# ---------------------------------------------------------------------------

cmd_review() {
  local video=${1:-}
  [ -n "$video" ] || die "usage: tests/demo.sh review <video>"
  [ -f "$video" ] || die "no such file: $video"
  command -v ffmpeg >/dev/null || die "ffmpeg is not installed"

  local frames="$demo_dir/frames"
  rm -rf -- "$frames"
  mkdir -p "$frames"
  head2 "Pulling a frame a second"
  ffmpeg -v error -i "$video" -vf fps=1 "$frames/%02d.jpg"
  say "   $(find "$frames" -name '*.jpg' | wc -l | tr -d ' ') frames in $frames"

  head2 "Watch the frames for"
  cat <<'LIST'
   [ ] a username or a home path anywhere: prompts, titles, file names
   [ ] a hostname in a terminal prompt or a window title
   [ ] neighbours' Wi-Fi names, if the network page was opened
   [ ] notification text or clipboard contents that are not yours to publish
   [ ] windows that have nothing to do with the demo
   [ ] the moment an event should have appeared: was it on screen?
LIST

  head2 "Size"
  local bytes
  bytes=$(stat -c %s "$video")
  say "   $(du -h "$video" | cut -f1) ($bytes bytes)"

  head2 "Trimming, without re-encoding"
  cat <<LIST
   ffmpeg -ss 3 -to 25 -i "$video" -c copy -avoid_negative_ts make_zero demo.mp4
   ffmpeg -i demo.mp4 -vf "fps=15,scale=1000:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse" demo.gif
LIST
  if [ "$bytes" -gt 10485760 ]; then
    say "   the mp4 is over 10 MB: trim it, or scale the gif below 1000px wide"
  fi
  return 0
}

# ---------------------------------------------------------------------------

case "${1:-}" in
  prepare) cmd_prepare ;;
  run)     cmd_run ;;
  cleanup) cmd_cleanup ;;
  status)  cmd_status ;;
  review)  shift; cmd_review "${1:-}" ;;
  *)
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
