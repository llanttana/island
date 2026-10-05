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

step "QML syntax"
qmllint_bin=$(command -v qmllint || echo /usr/lib/qt6/bin/qmllint)
if [ -x "$qmllint_bin" ]; then
  mapfile -t files < <(git ls-files '*.qml')
  if "$qmllint_bin" "${files[@]}" >/dev/null 2>&1; then
    ok "${#files[@]} files"
  else
    bad "qmllint"
    "$qmllint_bin" "${files[@]}" 2>&1 | grep -i "error" | head -10
  fi
else
  skip "qmllint is not installed"
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
