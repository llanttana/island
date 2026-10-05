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
for f in companion/*.sh tests/*.sh; do
  if bash -n "$f"; then ok "$f"; else bad "$f"; fi
done

step "shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -x --severity=warning companion/*.sh tests/*.sh; then ok "clean"; else bad "shellcheck reported problems"; fi
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
if git show --check --format=%h HEAD >/dev/null 2>&1; then ok "no whitespace errors in HEAD"; else bad "whitespace errors in HEAD"; fi

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

step "Companion setup tests"
if bash tests/run.sh; then ok "tests/run.sh"; else bad "tests/run.sh"; fi

printf '\n%s\n' "$([ $fail -eq 0 ] && echo 'all checks passed' || echo 'CHECKS FAILED')"
exit $fail
