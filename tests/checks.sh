#!/bin/bash
# Everything the project checks before a change lands. This is the script CI
# runs, and it is meant to work on a developer machine too: a missing tool is
# reported and skipped, so a fresh checkout without Qt or shellcheck still gets
# the rest of the checks instead of failing on the first one.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
cd "$root" || exit 1

fail=0
step() { printf '\n== %s\n' "$1"; }
ok()   { printf '   ok    %s\n' "$1"; }
bad()  { printf '   FAIL  %s\n' "$1"; fail=1; }
skip() { printf '   skip  %s\n' "$1"; }

step "Bash syntax"
shopt -s nullglob
for f in companion/*.sh tests/*.sh githooks/*; do
  if bash -n "$f"; then ok "$f"; else bad "$f"; fi
done

step "shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -x --severity=warning companion/*.sh tests/*.sh githooks/*; then ok "clean"; else bad "shellcheck reported problems"; fi
else
  skip "shellcheck is not installed"
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
    printf '%s\n' "$QMLLINT_OUTPUT" | grep -B2 -A3 '\[syntax\]' | sed -n '1,30p' | sed 's/^/        /'
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

step "Companion setup tests"
if bash tests/run.sh; then ok "tests/run.sh"; else bad "tests/run.sh"; fi

printf '\n%s\n' "$([ $fail -eq 0 ] && echo 'all checks passed' || echo 'CHECKS FAILED')"
exit $fail
