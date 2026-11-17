#!/usr/bin/env bash
# uninstall.sh: remove what scripts/install.sh installed, using its manifest.
#
#   scripts/uninstall.sh [--keep-settings] [--dry-run]
#
#   --keep-settings  Leave settings.json alone. By default the entries that came from
#                    settings/settings.snippet.json are removed (only if they still have the
#                    snippet's values); other settings are never touched.
#   --dry-run        Print what would change, change nothing.
#
# Symlinks that still point into this repo are removed. Copies are never deleted: they are moved
# to <config>/dev-team-backups/<timestamp>-uninstall/ (copied playbooks may hold learned lessons).
# Files that install.sh moved aside are restored. Agent memory (<config>/agent-memory/) and the
# .team/ folders in your projects are left untouched.

set -euo pipefail
export LC_ALL=C

REPO=$(cd -P "$(dirname "$0")/.." && pwd -P)
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
HOME_DIR="$CFG/dev-team"
MANIFEST="$HOME_DIR/.install-manifest"
OUT_DIR="$CFG/dev-team-backups/$(date +%Y%m%d-%H%M%S)-uninstall"

KEEP_SETTINGS=0; DRY=0
for arg in "$@"; do
  case "$arg" in
    --keep-settings) KEEP_SETTINGS=1 ;;
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg (see --help)" >&2; exit 2 ;;
  esac
done

say() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
run() { if [ "$DRY" = 1 ]; then say "  would: $*"; else "$@"; fi; }

[ -f "$MANIFEST" ] || { echo "Nothing to do: no install manifest at $MANIFEST" >&2; exit 0; }

removed=0; moved=0; restored=0; skipped=0
settings_note="not changed"

stash() { # move TARGET to the uninstall backup dir
  local rel="${1#"$CFG"/}"
  run mkdir -p "$(dirname "$OUT_DIR/$rel")"
  run mv "$1" "$OUT_DIR/$rel"
  moved=$((moved + 1))
}

# Pass 1: remove installed items.
while IFS="	" read -r kind target src; do
  case "$kind" in
    link)
      if [ -L "$target" ] && [ "$(readlink "$target")" = "$src" ]; then
        run unlink "$target"; removed=$((removed + 1))
      elif [ -e "$target" ] || [ -L "$target" ]; then
        warn "$target changed since install; left in place"; skipped=$((skipped + 1))
      fi ;;
    copy)
      if [ -e "$target" ]; then stash "$target"; fi ;;
    settings)
      [ "$KEEP_SETTINGS" = 1 ] && { settings_note="kept (--keep-settings)"; continue; }
      [ -f "$target" ] || continue
      snippet="$src"; [ -f "$snippet" ] || snippet="$REPO/settings/settings.snippet.json"
      if ! command -v jq >/dev/null 2>&1; then
        settings_note="not changed: jq is needed to remove the snippet's entries"; continue
      fi
      cleaned=$(jq --slurpfile snip "$snippet" --arg repo "$REPO" '
        $snip[0] as $s
        | (($s.permissions.additionalDirectories // []) + [$repo]) as $dirs
        | if .env then .env |= with_entries(select(.key as $k | ($s.env[$k] // null) != .value)) else . end
        | if .env == {} then del(.env) else . end
        | if .permissions.allow then
            .permissions.allow |= map(select(. as $r | any(($s.permissions.allow // [])[]; . == $r) | not))
          else . end
        | if .permissions.allow == [] then del(.permissions.allow) else . end
        | if .permissions.additionalDirectories then
            .permissions.additionalDirectories |= map(select(. as $d | any($dirs[]; . == $d) | not))
          else . end
        | if .permissions.additionalDirectories == [] then del(.permissions.additionalDirectories) else . end
        | if .permissions == {} then del(.permissions) else . end' "$target")
      if [ "$cleaned" = "$(jq . "$target")" ]; then
        settings_note="no snippet entries found"
      else
        run mkdir -p "$OUT_DIR"
        run cp -p "$target" "$OUT_DIR/settings.json"
        if [ "$DRY" = 1 ]; then say "  would: remove the snippet's entries from $target"
        else printf '%s\n' "$cleaned" > "$target.tmp.$$" && mv "$target.tmp.$$" "$target"; fi
        settings_note="snippet entries removed (backup: $OUT_DIR/settings.json)"
      fi ;;
  esac
done < "$MANIFEST"

# Pass 2: restore what install.sh moved aside.
while IFS="	" read -r kind target backup; do
  [ "$kind" = backup ] || continue
  if [ ! -e "$backup" ] && [ ! -L "$backup" ]; then
    warn "backup $backup is gone; cannot restore $target"; continue
  fi
  if [ -e "$target" ] || [ -L "$target" ]; then
    warn "$target exists again; backup left at $backup"; continue
  fi
  run mkdir -p "$(dirname "$target")"
  run mv "$backup" "$target"
  restored=$((restored + 1))
done < "$MANIFEST"

run unlink "$MANIFEST"
if [ "$DRY" = 0 ]; then rmdir "$HOME_DIR" 2>/dev/null || warn "$HOME_DIR is not empty; left in place"; fi

say ""
say "dev-team-agents $([ "$DRY" = 1 ] && echo '(dry run) ')uninstalled from $CFG"
say "  symlinks removed: $removed · copies moved aside: $moved · restored: $restored · left in place: $skipped"
say "  settings.json: $settings_note"
[ "$moved" -gt 0 ] && say "  moved copies: $OUT_DIR"
exit 0
