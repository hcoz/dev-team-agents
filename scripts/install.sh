#!/usr/bin/env bash
# install.sh: install dev-team-agents into the user's Claude Code config (default ~/.claude).
#
#   scripts/install.sh [--copy] [--with-settings] [--dry-run]
#
#   --copy           Copy files instead of symlinking them (symlinks are the default; a failed
#                    symlink falls back to a copy automatically).
#   --with-settings  Also merge settings/settings.snippet.json into settings.json: default budgets
#                    (env) and allow rules for the team's scripts. Existing values are kept.
#   --dry-run        Print what would change, change nothing.
#
# Installs:
#   agents/*.md        -> <config>/agents/<name>.md
#   skills/<name>/     -> <config>/skills/<name>
#   templates/, playbooks/, hooks/ -> <config>/dev-team/
# Anything already at a target that is not this install is moved to
# <config>/dev-team-backups/<timestamp>/ first. Re-running is safe (idempotent).
# The install is recorded in <config>/dev-team/.install-manifest for uninstall.sh.

set -euo pipefail
export LC_ALL=C

REPO=$(cd -P "$(dirname "$0")/.." && pwd -P)
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
HOME_DIR="$CFG/dev-team"
MANIFEST="$HOME_DIR/.install-manifest"
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="$CFG/dev-team-backups/$STAMP"
MIN_CLAUDE="2.1.295"

MODE=link; WITH_SETTINGS=0; DRY=0
for arg in "$@"; do
  case "$arg" in
    --copy) MODE=copy ;;
    --with-settings) WITH_SETTINGS=1 ;;
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg (see --help)" >&2; exit 2 ;;
  esac
done

say() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
run() { if [ "$DRY" = 1 ]; then say "  would: $*"; else "$@"; fi; }

# --- Checks --------------------------------------------------------------------------------------

command -v git >/dev/null 2>&1 || { echo "error: git is required" >&2; exit 1; }
if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
  echo "error: the guard hooks need jq or python3; install one of them first" >&2; exit 1
fi
if [ "$CFG" != "$HOME/.claude" ]; then
  warn "CLAUDE_CONFIG_DIR is $CFG. The agents' hooks and prompts use ~/.claude paths, so the team only works when the config dir is ~/.claude."
fi

version_ge() { # version_ge A B: is A >= B (dotted numbers)
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)" = "$2" ]
}
if command -v claude >/dev/null 2>&1; then
  v=$(claude --version 2>/dev/null | awk '{ print $1; exit }')
  if [ -n "$v" ] && ! version_ge "$v" "$MIN_CLAUDE"; then
    warn "Claude Code $v found; $MIN_CLAUDE or later is needed (hooks use onFailure: block)."
  fi
else
  warn "claude not found on PATH. The team needs Claude Code $MIN_CLAUDE or later."
fi

# --- Install -------------------------------------------------------------------------------------

ITEMS=""   # "source<TAB>target" lines
add_item() { ITEMS="$ITEMS$1	$2
"; }
for f in "$REPO"/agents/*.md; do add_item "$f" "$CFG/agents/${f##*/}"; done
for d in "$REPO"/skills/*/; do d="${d%/}"; add_item "$d" "$CFG/skills/${d##*/}"; done
for d in templates playbooks hooks; do add_item "$REPO/$d" "$HOME_DIR/$d"; done

# Make the shipped scripts executable in the source (copies keep the mode).
for f in "$REPO"/hooks/*.sh "$REPO"/skills/*/scripts/*.sh "$REPO"/scripts/*.sh; do
  [ -f "$f" ] && [ ! -x "$f" ] && run chmod +x "$f"
done

run mkdir -p "$CFG/agents" "$CFG/skills" "$HOME_DIR"

NEW_MANIFEST=""
installed=0; unchanged=0; backed_up=0

# State of a target: link (our symlink), copy (our up-to-date copy), stale (our copy, out of date
# or edited), foreign (anything else), none.
target_state() {
  if [ -L "$2" ] && [ "$(readlink "$2")" = "$1" ]; then echo link
  elif [ -e "$2" ] && grep -qF "$(printf 'copy\t%s\t%s' "$2" "$1")" "$MANIFEST" 2>/dev/null; then
    if diff -rq "$1" "$2" >/dev/null 2>&1; then echo copy; else echo stale; fi
  elif [ -e "$2" ] || [ -L "$2" ]; then echo foreign
  else echo none
  fi
}

# Move TARGET out of the way, keeping its path below CFG. Only foreign files are restorable:
# uninstall puts them back. Our own earlier copies go to the backup dir too, but are not restored.
backup() {
  local rel="${1#"$CFG"/}" dest
  dest="$BACKUP_DIR/$rel"
  [ "$2" = restorable ] || dest="$BACKUP_DIR/replaced/$rel"
  run mkdir -p "$(dirname "$dest")"
  run mv "$1" "$dest"
  if [ "$2" = restorable ]; then
    NEW_MANIFEST="${NEW_MANIFEST}backup	$1	$dest
"
    backed_up=$((backed_up + 1))
    warn "moved existing $1 to $dest"
  fi
}

USED=""
place() { # place SOURCE TARGET; sets USED to link or copy
  if [ "$MODE" = link ]; then
    if [ "$DRY" = 1 ]; then say "  would: ln -s $1 $2"; USED=link; return; fi
    if ln -s "$1" "$2" 2>/dev/null; then USED=link; return; fi
    warn "symlink failed for $2; copying instead"
  fi
  run cp -R -p "$1" "$2"
  USED=copy
}

while IFS="	" read -r src target; do
  [ -n "$src" ] || continue
  state=$(target_state "$src" "$target")
  if [ "$state" = "$MODE" ]; then
    USED="$MODE"
    unchanged=$((unchanged + 1))
  else
    case "$state" in
      link) run unlink "$target" ;;          # our symlink; switching to --copy
      copy) backup "$target" replaced ;;     # our copy; switching to symlinks
      stale) backup "$target" replaced
             warn "replaced the out-of-date copy at $target (old copy kept in $BACKUP_DIR/replaced/)" ;;
      foreign) backup "$target" restorable ;;
    esac
    place "$src" "$target"
    installed=$((installed + 1))
  fi
  NEW_MANIFEST="${NEW_MANIFEST}${USED}	$target	$src
"
done <<EOF
$ITEMS
EOF

# Keep backup lines from earlier installs, so uninstall can still restore them, and the settings
# line when this run does not merge settings itself, so uninstall still cleans them.
if [ -f "$MANIFEST" ]; then
  OLD_LINES=$(grep '^backup	' "$MANIFEST" || true)
  if [ "$WITH_SETTINGS" = 0 ]; then
    OLD_LINES="$OLD_LINES
$(grep '^settings	' "$MANIFEST" || true)"
  fi
  OLD_LINES=$(printf '%s\n' "$OLD_LINES" | sed '/^$/d')
  [ -n "$OLD_LINES" ] && NEW_MANIFEST="$NEW_MANIFEST$OLD_LINES
"
fi

# --- Settings ------------------------------------------------------------------------------------

SNIPPET="$REPO/settings/settings.snippet.json"
SETTINGS="$CFG/settings.json"
settings_note="not changed (use --with-settings to merge the snippet)"
if [ "$WITH_SETTINGS" = 1 ]; then
  command -v jq >/dev/null 2>&1 || { echo "error: --with-settings needs jq" >&2; exit 1; }
  current='{}'
  [ -f "$SETTINGS" ] && current=$(cat "$SETTINGS")
  merged=$(jq -n --argjson cur "$current" --slurpfile snip "$SNIPPET" '
    $snip[0] as $s
    | $cur
    | .env = (($s.env // {}) + (.env // {}))
    | .permissions.allow = (reduce ($s.permissions.allow // [])[] as $r
        ((.permissions.allow // []); if any(.[]; . == $r) then . else . + [$r] end))')
  if [ "$merged" = "$(printf '%s' "$current" | jq .)" ]; then
    settings_note="already contains the snippet"
  else
    if [ -f "$SETTINGS" ]; then
      run mkdir -p "$BACKUP_DIR"
      run cp -p "$SETTINGS" "$BACKUP_DIR/settings.json"
    fi
    if [ "$DRY" = 1 ]; then say "  would: merge $SNIPPET into $SETTINGS"
    else printf '%s\n' "$merged" > "$SETTINGS.tmp.$$" && mv "$SETTINGS.tmp.$$" "$SETTINGS"; fi
    settings_note="merged (backup: $BACKUP_DIR/settings.json)"
    [ -f "$BACKUP_DIR/settings.json" ] || settings_note="created"
  fi
  NEW_MANIFEST="${NEW_MANIFEST}settings	$SETTINGS	$SNIPPET
"
fi

if [ "$DRY" = 0 ]; then
  {
    echo "# dev-team-agents install manifest. Used by scripts/uninstall.sh. Do not edit."
    echo "# repo: $REPO"
    echo "# installed: $STAMP"
    printf '%s' "$NEW_MANIFEST"
  } > "$MANIFEST"
fi

say ""
say "dev-team-agents $([ "$DRY" = 1 ] && echo '(dry run) ')installed into $CFG"
say "  mode: $MODE · new or replaced: $installed · unchanged: $unchanged · backed up: $backed_up"
say "  settings.json: $settings_note"
[ "$backed_up" -gt 0 ] && say "  backups: $BACKUP_DIR"
say ""
say "Next: cd into a project and run:  claude --agent orchestrator"
exit 0
