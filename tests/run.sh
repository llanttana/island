#!/bin/bash
# Tests for the companion setup scripts. Two things are covered, because both
# are easy to get subtly wrong and quiet when they are: the edit that inserts
# entries into Omarchy's JSONC menu, and the timestamped backups.
#
# The menu cases are the shapes a real file comes in: empty, commented, missing
# trailing commas, extra trailing commas, CRLF line endings, and entries that
# are already there.
#
# Plain bash on purpose -- no bats, so the same command runs on a fresh machine
# and in CI with nothing installed but jq and perl.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
# shellcheck source=companion/lib.sh
source "$root/companion/lib.sh"

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

# Matches without ls, so odd file names cannot confuse the count.
count_of() { compgen -G "$1" | wc -l | tr -d ' '; }

# Sorted names in a directory without ls, so an odd name cannot break it.
list_names() {
  local dir=$1 pattern=$2 p
  for p in "$dir"/$pattern; do
    [[ -e $p ]] || continue
    basename "$p"
  done | sort | tr '\n' ' '
}

# The newest match by mtime, which is exactly what the backups sort on.
newest_backup() {
  find "$1" -maxdepth 1 -name "$2" -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-
}

mkdir -p "$work/menu"

# ---------------------------------------------------------------------------
section "menu_has_entry"

menu="$work/menu/plain.jsonc"
cat >"$menu" <<'JSON'
{
  "apps": {"action": "omarchy-menu toggle apps"},
  "system": {"action": "omarchy-shell lanta.island power"}
}
JSON
check "finds an entry that is there" "$(menu_has_entry "$menu" apps && echo yes || echo no)" "yes"
check "misses an entry that is not" "$(menu_has_entry "$menu" style.theme && echo yes || echo no)" "no"

# ---------------------------------------------------------------------------
section "menu_add_entry"

menu="$work/menu/empty.jsonc"
printf '{\n}\n' >"$menu"
menu_add_entry "$menu" '  "style.theme": {"action": "a"},'
menu_add_entry "$menu" '  "style.background": {"action": "b"},'
check "an empty object gains both entries" "$(grep -c ':' "$menu")" "2"
check "an empty object stays parseable" "$(menu_is_valid "$menu" && echo yes || echo no)" "yes"

menu="$work/menu/commented.jsonc"
cat >"$menu" <<'JSON'
{
  // the wallpaper row
  "apps": {"action": "theirs"}
}
JSON
menu_add_entry "$menu" '  "system": {"action": "ours"},'
check "a commented file stays parseable" "$(menu_is_valid "$menu" && echo yes || echo no)" "yes"
check "the comment survives" "$(grep -c '// the wallpaper row' "$menu")" "1"
check "the entry above gains a comma" "$(grep -c '"apps": {"action": "theirs"},' "$menu")" "1"
check "the new entry is there" "$(grep -c '"system"' "$menu")" "1"

menu="$work/menu/trailing.jsonc"
cat >"$menu" <<'JSON'
{
  "apps": {"action": "theirs"},
}
JSON
menu_add_entry "$menu" '  "system": {"action": "ours"},'
check "no doubled comma" "$(grep -c ',,$' "$menu")" "0"
check "a trailing-comma file stays parseable" "$(menu_is_valid "$menu" && echo yes || echo no)" "yes"

# CRLF is what a file edited on another machine looks like, and the brace regex
# still has to match its final line.
menu="$work/menu/crlf.jsonc"
printf '{\r\n  "apps": {"action": "theirs"}\r\n}\r\n' >"$menu"
menu_add_entry "$menu" '  "system": {"action": "ours"},'
check "a CRLF file gains the entry" "$(grep -c '"system"' "$menu")" "1"
check "a CRLF file stays parseable" "$(menu_is_valid "$menu" && echo yes || echo no)" "yes"

# A file with no closing brace must be refused, not mangled.
menu="$work/menu/broken.jsonc"
printf '{\n  "apps": {"action": "theirs"}\n' >"$menu"
before=$(cksum <"$menu")
rc=0
menu_add_entry "$menu" '  "system": {"action": "ours"},' || rc=1
check "a file with no closing brace is refused" "$rc" "1"
check "the refused file is untouched" "$(cksum <"$menu")" "$before"

# ---------------------------------------------------------------------------
section "backups"

# Pruning goes by mtime, so give every copy a distinct one.
dir="$work/prune"
mkdir -p "$dir"
for i in 1 2 3 4 5 6; do
  printf 'v%s\n' "$i" >"$dir/f.bak.2026010$i"
  touch -d "2026-01-0$i 00:00:00" "$dir/f.bak.2026010$i"
done
prune_backups "$dir/f" 3
check "prune_backups keeps the newest 3" "$(list_names "$dir" 'f.bak.*')" \
  "f.bak.20260104 f.bak.20260105 f.bak.20260106 "

dir="$work/keep"
mkdir -p "$dir"
f="$dir/cfg"
printf 'old\n' >"$f"
for i in 1 2 3 4 5; do
  printf 'v%s\n' "$i" >"$f.bak.2026010$i"
  touch -d "2026-01-0$i 00:00:00" "$f.bak.2026010$i"
done
printf 'new\n' >"$f"
backup_file "$f" 3 2>/dev/null
check "backup_file keeps the newest 3" "$(count_of "$dir/cfg.bak.*")" "3"
check "the copy just written is kept" "$(cat "$(newest_backup "$dir" 'cfg.bak.*')")" "new"
check "backup_file reports where it wrote" \
  "$(basename "$ISLAND_LAST_BACKUP" | grep -c '^cfg\.bak\.')" "1"
backup_file "$dir/nope" 3
check "backup_file ignores a missing file" "$ISLAND_LAST_BACKUP" ""

dir="$work/dirs"
mkdir -p "$dir"
for i in 1 2 3 4; do
  mkdir -p "$dir/.lanta.notifications.bak.0$i"
  touch -d "2026-01-0$i 00:00:00" "$dir/.lanta.notifications.bak.0$i"
done
prune_backup_dirs "$dir/.lanta.notifications.bak." 2
check "prune_backup_dirs keeps the newest 2" "$(list_names "$dir" '.lanta.notifications.bak.*')" \
  ".lanta.notifications.bak.03 .lanta.notifications.bak.04 "

# ---------------------------------------------------------------------------
section "install.sh end to end"

fake="$work/home"
mkdir -p "$fake/.config/omarchy/plugins" "$fake/.config/omarchy/extensions" "$work/bin"
for cmd in omarchy omarchy-plugin-validate omarchy-menu; do
  printf '#!/bin/bash\nexit 0\n' >"$work/bin/$cmd"
  chmod +x "$work/bin/$cmd"
done

shell_json="$fake/.config/omarchy/shell.json"
the_menu="$fake/.config/omarchy/extensions/omarchy-menu.jsonc"
printf '{\n  "bar": {"id": "omarchy.bar"}\n}\n' >"$shell_json"
cat >"$the_menu" <<'JSON'
{
  "apps": {"action": "omarchy-menu toggle apps"}
}
JSON

run_install() {
  ( cd "$root" && HOME="$fake" PATH="$work/bin:$PATH" bash companion/install.sh ) >/dev/null 2>&1
}

run_install
check "the companion lands in the plugin directory" \
  "$([[ -f $fake/.config/omarchy/plugins/lanta.notifications/Service.qml ]] && echo yes || echo no)" "yes"
check "shell.json enables the companion" \
  "$(jq -r '[.plugins[].id] | index("lanta.notifications") != null' "$shell_json")" "true"
check "shell.json disables the stock service" \
  "$(jq -r '.disabledPlugins | index("omarchy.notifications") != null' "$shell_json")" "true"
check "the first run backs shell.json up once" "$(count_of "$shell_json.bak.*")" "1"
check "the menu gains the island's theme entry" "$(grep -c 'lanta.island themes' "$the_menu")" "1"
check "an existing override is left alone" "$(grep -c 'omarchy-menu toggle apps' "$the_menu")" "1"
check "the edited menu is parseable" "$(menu_is_valid "$the_menu" && echo yes || echo no)" "yes"

run_install
check "a second, no-op run adds no backup" "$(count_of "$shell_json.bak.*")" "1"
check "a second, no-op run adds no second copy of an entry" \
  "$(grep -c 'lanta.island themes' "$the_menu")" "1"
check "a second run leaves one menu backup" "$(count_of "$the_menu.bak.*")" "1"

# ---------------------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
