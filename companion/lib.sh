#!/bin/bash
# Shared helpers for the companion setup scripts. This file is sourced, never
# executed, and never copied into the installed plugin (only lanta.notifications/
# is), so it stays a repository-side detail.
#
# Two things live here because both are easy to get wrong and worth testing on
# their own: the timestamped backups, and the menu edit that inserts entries
# before the final closing brace of a JSONC file.

# How many timestamped copies of a file to keep. The last one is always kept.
: "${ISLAND_BACKUP_KEEP:=5}"
# How many copies of a whole plugin directory to keep.
: "${ISLAND_BACKUP_DIRS_KEEP:=3}"

# Set by backup_file to the path it wrote, for callers that need to restore it.
# shellcheck disable=SC2034  # read by the scripts that source this file
ISLAND_LAST_BACKUP=""

# backup_file <path> [keep]
#
# Copies <path> to <path>.bak.<timestamp> and deletes all but the newest <keep>
# copies. Does nothing when <path> is not a regular file.
backup_file() {
  local path=$1 keep=${2:-$ISLAND_BACKUP_KEEP}
  ISLAND_LAST_BACKUP=""
  [[ -f $path ]] || return 0
  local stamp backup n
  stamp=$(date -u +%Y%m%d%H%M%S)
  backup="$path.bak.$stamp"
  n=1
  while [[ -e $backup ]]; do
    backup="$path.bak.$stamp-$n"
    n=$((n + 1))
  done
  cp -- "$path" "$backup"
  # shellcheck disable=SC2034  # read by the scripts that source this file
  ISLAND_LAST_BACKUP=$backup
  printf 'kept a copy at %s\n' "$backup" >&2
  prune_backups "$path" "$keep"
}

# prune_backups <path> [keep] -- newest first, deletes everything older.
prune_backups() {
  local path=$1 keep=${2:-$ISLAND_BACKUP_KEEP}
  local -a olds=()
  mapfile -t olds < <(ls -1t -- "$path".bak.* 2>/dev/null || true)
  [[ ${#olds[@]} -gt $keep ]] || return 0
  rm -f -- "${olds[@]:$keep}"
}

# prune_backup_dirs <prefix> [keep] -- the same, for directory backups whose
# names all start with <prefix>.
prune_backup_dirs() {
  local prefix=$1 keep=${2:-$ISLAND_BACKUP_DIRS_KEEP}
  local -a olds=()
  mapfile -t olds < <(ls -1dt -- "$prefix"* 2>/dev/null || true)
  [[ ${#olds[@]} -gt $keep ]] || return 0
  rm -rf -- "${olds[@]:$keep}"
}

# menu_has_entry <menu-file> <entry-id>
menu_has_entry() {
  grep -q "\"$2\"" "$1"
}

# menu_add_entry <menu-file> <entry-line>
#
# Inserts the line before the file's final closing brace, adding a comma to the
# entry above it when that entry does not already end in one. Leaves the file
# untouched when there is nothing that looks like a final brace.
menu_add_entry() {
  local menu=$1 entry=$2 tmp
  tmp=$(mktemp "$menu.XXXXXX")
  awk -v entry="$entry" '
    { lines[NR] = $0 }
    /^[[:space:]]*}[[:space:]]*$/ { last = NR }
    END {
      if (last == 0) { exit 1 }
      for (i = last - 1; i >= 1; i--) if (lines[i] !~ /^[[:space:]]*(\/\/.*)?$/) break
      if (i >= 1 && lines[i] !~ /[{,][[:space:]]*$/) sub(/[[:space:]]*$/, ",", lines[i])
      for (i = 1; i <= NR; i++) {
        if (i == last) print entry
        print lines[i]
      }
    }' "$menu" >"$tmp" || { rm -f -- "$tmp"; return 1; }
  mv -- "$tmp" "$menu"
}

# menu_is_valid <menu-file>
#
# Omarchy drops every whole-line // comment and every trailing comma and then
# parses the rest as JSON; a file it cannot parse loses all of its overrides.
# This is that same pass, so the caller can put the original back.
menu_is_valid() {
  perl -0pe 's#^\s*//[^\n]*(\n|$)##gm; s#,(\s*[}\]])#$1#g' "$1" | jq -e 'type == "object"' >/dev/null 2>&1
}
