#!/usr/bin/env bash
# allow-web.sh: PreToolUse hook that lets the Architect use WebSearch and WebFetch without a
# permission prompt, up to a lookup cap per agent.
#
#   allow-web.sh architect       wired in the Architect's frontmatter for WebSearch|WebFetch
#
# A background subagent cannot show a permission prompt, so without this hook every lookup is
# denied and versions in a stack proposal or design end up "unverified". A user-level allow rule
# would also apply to the owner's own sessions; this hook applies only where it is wired.
#   WebSearch                       allow
#   WebFetch of an https:// URL     allow
#   anything else, or over the cap  no decision: the normal permission flow decides
# The cap (DEV_TEAM_WEB_LIMIT, default 15 per agent) backs up the prompt's ~10 lookups.
# Works with macOS bash 3.2. Needs jq or python3 to read the hook input.

set -u
export LC_ALL=C

ROLE="${1:-}"
LIMIT="${DEV_TEAM_WEB_LIMIT:-15}"
INPUT=$(cat)

get() { # get FIELD: tool_name | url | agent_id | session_id
  if command -v jq >/dev/null 2>&1; then
    case "$1" in
      url) printf '%s' "$INPUT" | jq -r '.tool_input.url // ""' ;;
      *) printf '%s' "$INPUT" | jq -r --arg k "$1" '.[$k] // ""' ;;
    esac
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$INPUT" | python3 -I -c '
import json, sys
d = json.load(sys.stdin)
v = (d.get("tool_input") or {}).get("url") if sys.argv[1] == "url" else d.get(sys.argv[1])
print(v or "", end="")
' "$1"
  fi
}

[ "$ROLE" = architect ] || exit 0
tool=$(get tool_name)
case "$tool" in
  WebSearch) ;;
  WebFetch) case "$(get url)" in https://*) ;; *) exit 0 ;; esac ;;
  *) exit 0 ;;
esac

# Count lookups per agent (the main session has no agent_id: count per session instead).
key=$(get agent_id); [ -n "$key" ] || key="session-$(get session_id)"
case "$key" in *[!A-Za-z0-9_-]*) exit 0 ;; esac
dir="${TMPDIR:-/tmp}/dev-team-web"
mkdir -p "$dir" 2>/dev/null || exit 0
n=$(cat "$dir/$key" 2>/dev/null || echo 0)
case "$n" in ''|*[!0-9]*) n=0 ;; esac
[ "$n" -lt "$LIMIT" ] || exit 0
echo $((n + 1)) > "$dir/$key"

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"allow-web: architect lookup %s of %s"}}\n' "$((n + 1))" "$LIMIT"
exit 0
