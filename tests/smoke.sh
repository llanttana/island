#!/bin/bash
# Is the island actually running? This one needs a live Omarchy session, so it
# is not part of tests/checks.sh and not part of CI -- it is the check to run by
# hand after deploying.
#
# It exists because a plugin that fails to load does not fail loudly: Omarchy
# writes one WARN line, falls back to its own bar and disables the plugin, so
# the visible symptom is a bar that looks perfectly normal and no island.
set -uo pipefail

fail=0
step() { printf '\n== %s\n' "$1"; }
ok()   { printf '   ok    %s\n' "$1"; }
bad()  { printf '   FAIL  %s\n' "$1"; fail=1; }

step "Restarting the shell"
omarchy restart shell >/dev/null 2>&1 || true
sleep 8

step "The island's layer"
# Captured rather than piped into grep -q: that would let grep exit early, hand
# SIGPIPE to hyprctl, and fail the pipeline under `set -o pipefail` even on a
# match.
layers=$(hyprctl layers 2>/dev/null || true)
case $layers in
  *"namespace: omarchy-island"*)
    ok "omarchy-island is on screen"
    ;;
  *)
    bad "no omarchy-island layer -- the plugin did not load"
    printf '%s\n' "$layers" | grep -oE "namespace: [a-z-]+" | sort -u | sed 's/^/        /' || true
    ;;
esac

step "The plugin answers"
if timeout 10 omarchy-shell lanta.island toggle >/dev/null 2>&1; then
  ok "the IPC target responds"
else
  bad "lanta.island did not answer over IPC"
fi
timeout 10 omarchy-shell lanta.island toggle >/dev/null 2>&1 || true

step "QML warnings from the current shell"
pid=$(journalctl --user -b --no-pager 2>/dev/null | grep -v runner.js | grep -oE "omarchy-shell\[[0-9]+\]" | tail -1 | grep -oE "[0-9]+")
if [ -z "$pid" ]; then
  bad "could not find the running shell in the journal"
else
  # sed rather than head: head would leave the greps with SIGPIPE, and pipefail
  # would then report a failed pipeline for a scan that actually found things.
  warn=$(journalctl --user -b --no-pager 2>/dev/null | grep "\[$pid\]" \
    | grep -iE "WARN scene|TypeError|failed to load" | grep -v IpcHandler | sed -n '1,5p')
  if [ -z "$warn" ]; then
    ok "nothing from this shell instance"
  else
    bad "warnings from shell pid $pid"
    printf '%s\n' "$warn" | sed 's/^/        /'
  fi
fi

printf '\n%s\n' "$([ $fail -eq 0 ] && echo 'island is up' || echo 'SMOKE CHECK FAILED')"
exit $fail
