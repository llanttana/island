#!/bin/bash
# Everything the project checks before a change lands. This is the script CI
# runs, and it is meant to work on a developer machine too: a missing tool is
# reported and skipped, so a fresh checkout without Qt or shellcheck still gets
# the rest of the checks instead of failing on the first one. Shellcheck is the
# exception: a missing shellcheck says so on its own WARN line and is counted in
# the summary, and ISLAND_REQUIRE_SHELLCHECK=1 turns the absence into a failure
# rather than a quiet pass.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
cd "$root" || exit 1

fail=0
skipped=0
step() { printf '\n== %s\n' "$1"; }
ok()   { printf '   ok    %s\n' "$1"; }
bad()  { printf '   FAIL  %s\n' "$1"; fail=1; }
skip() { printf '   skip  %s\n' "$1"; skipped=$((skipped + 1)); }
warn() { printf '   WARN  %s\n' "$1"; }

step "Bash syntax"
shopt -s nullglob
for f in companion/*.sh tests/*.sh githooks/*; do
  if bash -n "$f"; then ok "$f"; else bad "$f"; fi
done

step "shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -x --severity=warning companion/*.sh tests/*.sh githooks/*; then ok "clean"; else bad "shellcheck reported problems"; fi
else
  # A bare `skip` inside a run that still ends in "all checks passed" is a
  # check people believe ran. Say it in full, count it, and let anyone who
  # wants a hard gate -- CI, a strict clone -- set ISLAND_REQUIRE_SHELLCHECK=1.
  warn "shellcheck is not installed: no shell file was checked"
  printf '   WARN  install shellcheck, or set ISLAND_REQUIRE_SHELLCHECK=1 to fail on its absence\n'
  skipped=$((skipped + 1))
  if [ "${ISLAND_REQUIRE_SHELLCHECK:-0}" = 1 ]; then
    bad "shellcheck is required but was not found"
  fi
fi

step "Manifests are valid JSON"
if command -v jq >/dev/null 2>&1; then
  for f in manifest.json companion/lanta.notifications/manifest.json; do
    if jq -e . "$f" >/dev/null; then ok "$f"; else bad "$f"; fi
  done
else
  skip "jq is not installed"
fi

step "Whitespace"
# In a commit hook there is something staged, and that is the diff that matters.
# In CI nothing is staged, so it is the commit that was just pushed.
if ! git diff --cached --quiet 2>/dev/null; then
  if git diff --cached --check; then ok "no whitespace errors in the staged changes"; else bad "whitespace in the staged changes"; fi
elif git show --check --format=%h HEAD >/dev/null 2>&1; then
  ok "no whitespace errors in HEAD"
else
  bad "whitespace errors in HEAD"
fi

# A pipe into `grep -q` is a trap here: grep exits on the first match, the
# writing side takes SIGPIPE, and `set -o pipefail` turns that into a failed
# pipeline -- so the condition reads as "not found" exactly when it was found.
# This does the same job with no process in between.
contains() {
  case $1 in
    *"$2"*) return 0 ;;
    *) return 1 ;;
  esac
}

# How the last qmllint run ended: its output, and its exit code.
QMLLINT_OUTPUT=""
QMLLINT_RC=0

# qmllint tags parse errors with [syntax] when it can classify them, but that
# tag is not always there: on the CI runner the very same broken file came back
# as a bare "Expected token `;'" with no category, while the local run had the
# tag. Both count. A syntax error is the one thing that must never be missed --
# it takes the whole plugin down -- so the match is deliberately loose here and
# the negative test below is what keeps it honest.
is_syntax_error() {
  contains "$1" '[syntax]' && return 0
  case $1 in
    *"Expected token"* | *"Unexpected token"* | *"Expected end"*) return 0 ;;
  esac
  return 1
}

# Run qmllint and leave both behind. Returns 0 when it reported a syntax error,
# 1 when it did not. The negative test below calls this same function, so what
# it exercises is the real check and not a second copy of it.
qmllint_run() {
  local bin=$1
  shift
  QMLLINT_RC=0
  QMLLINT_OUTPUT=$("$bin" "$@" 2>&1) || QMLLINT_RC=$?
  is_syntax_error "$QMLLINT_OUTPUT"
}

step "QML syntax"
qmllint_bin=$(command -v qmllint || echo /usr/lib/qt6/bin/qmllint)
if [ -x "$qmllint_bin" ]; then
  mapfile -t files < <(git ls-files '*.qml')
  # A runner has neither Quickshell nor, without extra packages, the Qt QML
  # modules, so qmllint there resolves no types at all and every file is a pile
  # of import warnings. Checking only syntax is the honest thing to ask of it:
  # ISLAND_LINT_SYNTAX_ONLY=1 turns the type warnings off and keeps the syntax
  # errors, which are the ones that take the whole plugin down. The full lint
  # stays a local check, where the types are there.
  syntax_only=${ISLAND_LINT_SYNTAX_ONLY:-0}
  qmllint_run "$qmllint_bin" "${files[@]}" && syntax_found=1 || syntax_found=0
  if [ "$syntax_found" = "1" ]; then
    bad "qmllint found syntax errors"
    # The lines that matched, then the head: the first says what was mistaken for
    # a syntax error, the second shows the context.
    printf '        qmllint exit code: %s\n' "$QMLLINT_RC"
    printf '        matched:\n'
    printf '%s\n' "$QMLLINT_OUTPUT" | grep -nE '\[syntax\]|Expected|Unexpected' | sed -n '1,8p' | sed 's/^/          /'
    printf '        head:\n'
    printf '%s\n' "$QMLLINT_OUTPUT" | sed -n '1,6p' | sed 's/^/          /'
  elif [ "$syntax_only" = "1" ]; then
    ok "${#files[@]} files, no syntax errors (types are not resolved here)"
  elif [ "$QMLLINT_RC" -ne 0 ]; then
    # Warnings are normal here -- unresolved first-party services, unqualified
    # access in nested components -- so the exit code decides, not the output.
    bad "qmllint"
    printf '%s\n' "$QMLLINT_OUTPUT" | sed -n '1,25p' | sed 's/^/        /'
  else
    ok "${#files[@]} files"
  fi
else
  skip "qmllint is not installed"
fi

step "The QML check fails on broken QML"
# Being told "ok" is only worth something if the check can say otherwise. This
# proves the detection fires, and that it is not simply failing on everything.
if [ ! -x "$qmllint_bin" ]; then
  skip "qmllint is not installed, so there is nothing to test"
elif [ ! -f "$root/tests/fixtures/broken-qml.txt" ]; then
  bad "the fixture is missing: tests/fixtures/broken-qml.txt"
else
  fixture_dir=$(mktemp -d)
  cp "$root/tests/fixtures/broken-qml.txt" "$fixture_dir/broken.qml"
  cp "$root/tests/fixtures/valid-qml.txt" "$fixture_dir/valid.qml"
  if qmllint_run "$qmllint_bin" "$fixture_dir/broken.qml"; then
    ok "the broken fixture is reported as a syntax error"
  else
    bad "the broken fixture was NOT reported -- the syntax check cannot be trusted"
    printf '        qmllint exit code: %s\n' "$QMLLINT_RC"
    printf '%s\n' "$QMLLINT_OUTPUT" | sed -n '1,10p' | sed 's/^/        /'
  fi
  if qmllint_run "$qmllint_bin" "$fixture_dir/valid.qml"; then
    bad "a valid file was reported as a syntax error"
  else
    ok "a valid file is left alone"
  fi
  rm -rf -- "$fixture_dir"
fi

step "QML handlers"
# A second Component.onCompleted on the same object is a QML error, and a bad
# one: the file stops loading, and for a bar plugin that means Omarchy falls
# back to its own bar and disables the island. qmllint does not catch it, an
# accidental duplicate on the root always starts its line, and a mention inside
# a comment never does -- hence anchoring to the start of the line. Two objects
# in one file may each have one, which this would flag; no file here does.
dups=0
while IFS= read -r f; do
  n=$(grep -c "^[[:space:]]*Component\.onCompleted" "$f")
  if [ "$n" -gt 1 ]; then bad "$f has $n Component.onCompleted"; dups=1; fi
done < <(git ls-files '*.qml')
[ "$dups" -ne 0 ] || ok "no file declares Component.onCompleted twice"

step "Notification logic"
# The transient branch, exercised against the real isEphemeral() lifted out of
# Service.qml. Node is not a dependency of the plugin; where it is missing the
# step says so rather than failing.
if command -v node >/dev/null 2>&1; then
  rc=0
  out=$(node "$root/tests/ephemeral.test.js" 2>&1) || rc=1
  printf '%s\n' "$out" | sed 's/^/        /'
  if [ "$rc" -eq 0 ]; then
    ok "the transient branch behaves as documented"
  else
    bad "tests/ephemeral.test.js"
  fi
else
  skip "node is not installed, so the notification logic cannot be exercised"
fi

# The activity model is pure logic as well: order, what the pill shows and what
# is left over. Same node-or-skip treatment as the notification logic above.
if command -v node >/dev/null 2>&1; then
  rc=0
  out=$(node "$root/tests/activity.test.js" 2>&1) || rc=1
  if [[ $rc -eq 0 ]]; then ok "tests/activity.test.js"; else bad "tests/activity.test.js"; printf '%s\n' "$out" | sed 's/^/       /'; fi
else
  skip "node is not installed, so the activity model cannot be exercised"
fi

# Which provider the launcher's Ask row runs is pure logic as well: the setting
# and which CLIs are installed decide it.
if command -v node >/dev/null 2>&1; then
  rc=0
  out=$(node "$root/tests/ask-providers.test.js" 2>&1) || rc=1
  if [[ $rc -eq 0 ]]; then ok "tests/ask-providers.test.js"; else bad "tests/ask-providers.test.js"; printf '%s\n' "$out" | sed 's/^/       /'; fi
else
  skip "node is not installed, so the Ask provider choice cannot be exercised"
fi

# The legacy pill rules the model has to reproduce are frozen in
# tests/fixtures/island-legacy-pills.qml. This reads that freeze and not
# Island.qml: stage 2 rewrites the very lines it was cut from, and the reference
# is the thing that has to stand still while that happens. The comparison with
# the live sources is `node tests/pill-legacy.test.js --verify-live`, kept out of
# this script on purpose -- it is expected to differ once the sources move.
if command -v node >/dev/null 2>&1; then
  rc=0
  out=$(node "$root/tests/pill-legacy.test.js" 2>&1) || rc=1
  if [[ $rc -eq 0 ]]; then ok "tests/pill-legacy.test.js"; else bad "tests/pill-legacy.test.js"; printf '%s\n' "$out" | sed 's/^/       /'; fi
else
  skip "node is not installed, so the legacy pill reference cannot be exercised"
fi

step "Companion setup tests"
if bash tests/run.sh; then ok "tests/run.sh"; else bad "tests/run.sh"; fi

step "Demo scene tests"
if bash tests/demo.test.sh; then ok "tests/demo.test.sh"; else bad "tests/demo.test.sh"; fi

if [ "$fail" -ne 0 ]; then
  printf '\n%s\n' 'CHECKS FAILED'
elif [ "$skipped" -ne 0 ]; then
  printf '\n%s\n' "all checks passed, but $skipped check(s) were skipped -- see above"
else
  printf '\n%s\n' 'all checks passed'
fi
exit $fail
