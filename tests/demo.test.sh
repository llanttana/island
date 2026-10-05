#!/bin/bash
# Tests for tests/demo.sh. The script empties the scene before a recording and
# puts it back afterwards, and both halves move the person's real notification
# and clipboard history -- so the cases worth pinning are the ones where it must
# not touch them, and the one where it must put them back exactly.
#
# The shell's IPC is stubbed and HOME points at a throwaway directory, so this
# touches nothing of the machine it runs on; the stubs also record every call,
# which is how the test can prove that a bare cleanup never asks the companion
# to clear anything. The timeline is compressed with ISLAND_DEMO_SPEED, so the
# run costs about a second instead of twenty.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)

pass=0
fail=0
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

ok() { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad() {
  fail=$((fail + 1))
  printf '  FAIL  %s\n' "$1"
  [[ $# -gt 1 ]] && printf '        %s\n' "$2"
  return 0
}
check() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1" "expected [$3], got [$2]"; fi; }
section() { printf '\n%s\n' "$1"; }

# The names and the bytes together, so a delete and a rename both show up.
dir_hash() {
  local dir=$1
  { ls -1 "$dir" 2>/dev/null; cat "$dir"/*.json 2>/dev/null; } | md5sum | cut -d' ' -f1
}
files_in() { compgen -G "$1/*" 2>/dev/null | wc -l | tr -d ' '; }

# ---------------------------------------------------------------------------
# The stubs. The real omarchy-shell would reach the session of whoever runs the
# tests, whatever HOME says, so it is replaced -- and so is the notification
# sender, which would otherwise pop a toast on their screen.

stub_bin="$work/bin"
mkdir -p "$stub_bin"
for cmd in omarchy-shell omarchy-notification-send; do
  cat >"$stub_bin/$cmd" <<'STUB'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"${DEMO_CALL_LOG:-/dev/null}"
case "${1:-} ${2:-}" in
  "notifications dndState") printf 'off\n' ;;
esac
exit 0
STUB
  chmod +x "$stub_bin/$cmd"
done

# One throwaway session: a HOME holding some history, its own demo directory and
# its own call log.
make_session() {
  local home="$work/$1/home"
  mkdir -p "$home/.local/state/omarchy/notifications/history"
  printf '{"id":1,"timestamp":1,"summary":"keep me"}\n' \
    >"$home/.local/state/omarchy/notifications/history/11-1.json"
  printf '{"id":2,"timestamp":2,"summary":"keep me too"}\n' \
    >"$home/.local/state/omarchy/notifications/history/22-2.json"
  printf '[{"text":"keep me as well"}]' >"$home/.local/state/omarchy/clipboard-history.json"
  : >"$work/$1/calls.log"
}

run_demo() {
  local name=$1
  shift
  ( cd "$root" && HOME="$work/$name/home" \
      DEMO_CALL_LOG="$work/$name/calls.log" \
      ISLAND_DEMO_DIR="$work/$name/demo" \
      ISLAND_DEMO_SPEED=10 \
      PATH="$stub_bin:$PATH" bash tests/demo.sh "$@" ) >/dev/null 2>&1
}

hist_of() { printf '%s' "$work/$1/home/.local/state/omarchy/notifications/history"; }
clip_of() { printf '%s' "$work/$1/home/.local/state/omarchy/clipboard-history.json"; }
calls_of() { printf '%s' "$work/$1/calls.log"; }

# ---------------------------------------------------------------------------
section "cleanup with nothing prepared"

# `companion clear` wipes the notification history, and with no backup the
# restore has nothing to copy: this is the case that used to lose it.
make_session bare
before=$(dir_hash "$(hist_of bare)")
run_demo bare cleanup
check "the history is left alone" "$(dir_hash "$(hist_of bare)")" "$before"
check "the history still holds both entries" "$(files_in "$(hist_of bare)")" "2"
check "the companion is not asked to clear" \
  "$(grep -c 'notifications clear' "$(calls_of bare)" || true)" "0"

# ---------------------------------------------------------------------------
section "prepare, run, cleanup"

make_session trip
before=$(dir_hash "$(hist_of trip)")
before_clip=$(cat "$(clip_of trip)")

run_demo trip prepare
check "prepare empties the live history" "$(files_in "$(hist_of trip)")" "0"
check "prepare keeps the backup" \
  "$([[ -d $work/trip/demo/backup/notifications-history ]] && echo yes || echo no)" "yes"

run_demo trip run
check "the run fires both notifications" \
  "$(grep -c 'omarchy-notification-send' "$(calls_of trip)" || true)" "2"

run_demo trip cleanup
check "the history comes back byte for byte" "$(dir_hash "$(hist_of trip)")" "$before"
check "both entries are back" "$(files_in "$(hist_of trip)")" "2"
check "the clipboard comes back" "$(cat "$(clip_of trip)")" "$before_clip"
check "cleanup clears the companion exactly once" \
  "$(grep -c 'notifications clear' "$(calls_of trip)" || true)" "1"

# ---------------------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
