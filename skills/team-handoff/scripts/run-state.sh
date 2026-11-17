#!/usr/bin/env bash
# run-state.sh: deterministic bookkeeping for a dev-team run (Orchestrator only).
#
#   run-state.sh new PROJECT SLUG                 Create .team/runs/<run-id>/ with state.md and logs/.
#   run-state.sh files RUN_DIR NAME...            Add run files from templates if missing
#                                                 (requirements design tasks test-report).
#   run-state.sh active PROJECT                   List unfinished runs (active, waiting-for-owner, blocked).
#   run-state.sh budget RUN_DIR SIZE [SOFT HARD]  Set the run's budgets: explicit values, else the profile's
#                                                 Budget overrides, else DEV_TEAM_BUDGET_<SIZE>_SOFT|HARD,
#                                                 else built-in defaults.
#   run-state.sh usage RUN_DIR AGENT_ID AGENT STEP ROUND STATUS
#                                                 Add a usage-log row for one finished agent call, from the
#                                                 subagent transcript; then print the budget check.
#   run-state.sh check RUN_DIR                    Print the budget check.
#   run-state.sh ack-soft RUN_DIR                 Record that the owner chose to continue past the soft budget.
#   run-state.sh rework RUN_DIR TASK [--force]    Start a rework round for TASK if both caps allow it.
#
# Budget check output: "spent: N", "soft: N", "hard: N", "level: ok|soft|hard".
#   soft = soft budget reached and not yet acknowledged; hard = hard budget reached.
# Tokens are input-token equivalents: input + 1.25 x cache writes + 0.1 x cache reads + 5 x output,
# summed over every API request in the agent's transcript that was not counted before.
#
# Exit codes: 0 ok, 2 usage or input error, 3 rework cap reached. Works with macOS bash 3.2.
# Needs jq or python3 for "usage".

set -euo pipefail
export LC_ALL=C

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
TEMPLATES="${DEV_TEAM_HOME:-$CFG/dev-team}/templates/team"
TASK_CAP="${DEV_TEAM_REWORK_TASK_CAP:-3}"
RUN_CAP="${DEV_TEAM_REWORK_RUN_CAP:-8}"

die() { echo "error: $*" >&2; exit 2; }

state_of() {
  [ -f "$1/state.md" ] || die "no state.md in $1"
  printf '%s/state.md' "$1"
}

# --- Markdown table helpers (operate on one "## Section" of a file) -------------------------------

# table_get FILE SECTION KEY: print the second cell of the row whose first cell is KEY.
table_get() {
  awk -v sec="$2" -v key="$3" -F'|' '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    /^## / { insec = ($0 == sec); next }
    insec && /^\|/ && trim($2) == key { print trim($3); exit }
  ' "$1"
}

# table_set FILE SECTION KEY VALUE: replace the second cell of the row whose first cell is KEY.
table_set() {
  local tmp="$1.tmp.$$"
  awk -v sec="$2" -v key="$3" -v val="$4" -F'|' '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    /^## / { insec = ($0 == sec) }
    insec && !done && /^\|/ && trim($2) == key {
      out = "|"
      for (i = 2; i < NF; i++) out = out " " (i == 3 ? val : trim($i)) " |"
      print out; done = 1; next
    }
    { print }
  ' "$1" > "$tmp" && mv "$tmp" "$1"
}

# table_add FILE SECTION HEADER ROW [BEFORE]: add ROW to the table whose first header cell is HEADER,
# as its last row, or before the row whose first cell is BEFORE.
table_add() {
  local tmp="$1.tmp.$$"
  awk -v sec="$2" -v hdr="$3" -v row="$4" -v before="${5:-}" -F'|' '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    { line[NR] = $0; first[NR] = trim($2) }
    END {
      insec = 0; intable = 0; target = 0; at = 0
      for (i = 1; i <= NR; i++) {
        if (line[i] ~ /^## /) { insec = (line[i] == sec); intable = 0; continue }
        if (!insec) continue
        if (line[i] ~ /^\|/) {
          if (!intable) { intable = 1; target = (first[i] == hdr) }
          if (target) {
            if (before != "" && first[i] == before) { at = i - 1; break }
            at = i
          }
        } else if (intable) {
          intable = 0
          if (target) break
        }
      }
      if (!at) { print "error: table \"" hdr "\" not found in " sec > "/dev/stderr"; exit 2 }
      for (i = 1; i <= NR; i++) { print line[i]; if (i == at) print row }
    }
  ' "$1" > "$tmp" && mv "$tmp" "$1"
}

# Count the data rows of the table whose first header cell is HEADER.
table_rows() {
  awk -v sec="$2" -v hdr="$3" -F'|' '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    /^## / { insec = ($0 == sec); intable = 0; next }
    !insec { next }
    /^\|/ {
      if (!intable) { intable = 1; target = (trim($2) == hdr); skip = 2 }
      if (target) { if (skip > 0) skip--; else n++ }
      next
    }
    { intable = 0 }
    END { print n + 0 }
  ' "$1"
}

is_number() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

# --- Commands -----------------------------------------------------------------------------------

cmd_new() {
  local project="${1:-}" slug="${2:-}"
  [ -d "$project" ] || die "usage: new PROJECT SLUG (PROJECT must exist)"
  slug=$(printf '%s' "$slug" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9' '-' | sed 's/^-*//; s/-*$//' | cut -c1-40)
  [ -n "$slug" ] || die "usage: new PROJECT SLUG (SLUG must contain letters or digits)"
  [ -f "$TEMPLATES/state.md" ] || die "templates not found in $TEMPLATES"
  project=$(cd -P "$project" && pwd -P)

  local team="$project/.team" base id n=2
  base="$(date +%Y-%m-%d)-$slug"
  id="$base"
  while [ -e "$team/runs/$id" ]; do id="$base-$n"; n=$((n + 1)); done
  local run="$team/runs/$id"
  mkdir -p "$run/logs"

  sed -e "s/<run-id>/$id/g" -e "s/<YYYY-MM-DD-slug>/$id/g" "$TEMPLATES/state.md" > "$run/state.md"
  # The header table sits above the first "##": set Created and Status directly.
  local tmp="$run/state.md.tmp.$$"
  awk -v now="$(date '+%Y-%m-%d %H:%M')" '
    /^\| Created \|/ && !c { print "| Created | " now " |"; c = 1; next }
    /^\| Status \|/ && !s { print "| Status | active |"; s = 1; next }
    { print }
  ' "$run/state.md" > "$tmp" && mv "$tmp" "$run/state.md"

  if [ ! -f "$team/learnings.md" ]; then
    sed "s/<project name>/${project##*/}/g" "$TEMPLATES/learnings.md" > "$team/learnings.md"
  fi
  if ! grep -qx 'runs/' "$team/.gitignore" 2>/dev/null; then
    echo 'runs/' >> "$team/.gitignore"
  fi

  echo "run_id: $id"
  echo "run_dir: $run"
}

cmd_files() {
  local run="${1:-}"; shift || true
  state_of "$run" >/dev/null
  local id="${run##*/}" name
  [ $# -gt 0 ] || die "usage: files RUN_DIR NAME..."
  for name in "$@"; do
    case "$name" in
      requirements|design|tasks|test-report) ;;
      *) die "unknown run file: $name (requirements, design, tasks, test-report)" ;;
    esac
    if [ -f "$run/$name.md" ]; then
      echo "exists: $run/$name.md"
    else
      sed "s/<run-id>/$id/g" "$TEMPLATES/$name.md" > "$run/$name.md"
      echo "created: $run/$name.md"
    fi
  done
}

cmd_active() {
  local project="${1:-}" f status
  [ -d "$project" ] || die "usage: active PROJECT"
  for f in "$project"/.team/runs/*/state.md; do
    [ -f "$f" ] || continue
    status=$(awk -F'|' '/^\| Status \|/ { gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3; exit }' "$f")
    case "$status" in
      active|waiting-for-owner|blocked)
        printf 'run: %s\tstatus: %s\tstep: %s\n' "$(dirname "$f")" "$status" \
          "$(awk -F'|' '/^\| Current step \|/ { gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3; exit }' "$f")" ;;
    esac
  done
}

default_budget() {
  case "$1-$2" in
    S-soft) echo 600000 ;;  S-hard) echo 1200000 ;;
    M-soft) echo 1500000 ;; M-hard) echo 3000000 ;;
    L-soft) echo 4000000 ;; L-hard) echo 8000000 ;;
  esac
}

# Budget for SIZE and KIND (soft|hard): project profile override, then env, then default.
resolve_budget() {
  local run="$1" size="$2" kind="$3" profile value col var
  profile="$(dirname "$(dirname "$run")")/project-profile.md"
  if [ -f "$profile" ]; then
    [ "$kind" = soft ] && col=3 || col=4
    value=$(awk -v size="$size" -v col="$col" -F'|' '
      function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
      /^## / { insec = ($0 == "## Budget overrides"); next }
      insec && /^\|/ && trim($2) == size { print trim($col); exit }
    ' "$profile" | tr -d ' _,')
    if is_number "$value"; then echo "$value"; return; fi
  fi
  var="DEV_TEAM_BUDGET_${size}_$(printf '%s' "$kind" | tr 'a-z' 'A-Z')"
  value="${!var:-}"
  if is_number "$value"; then echo "$value"; return; fi
  default_budget "$size" "$kind"
}

budget_check() {
  local state="$1" spent soft hard ack level=ok
  spent=$(table_get "$state" "## Budget" "Spent so far")
  soft=$(table_get "$state" "## Budget" "Soft budget")
  hard=$(table_get "$state" "## Budget" "Hard budget")
  ack=$(table_get "$state" "## Budget" "Soft budget acknowledged")
  is_number "$spent" || spent=0
  if ! is_number "$soft" || ! is_number "$hard"; then
    echo "spent: $spent"; echo "soft: unset"; echo "hard: unset"; echo "level: unset"
    return
  fi
  if [ "$spent" -ge "$hard" ]; then level=hard
  elif [ "$spent" -ge "$soft" ] && [ "$ack" != yes ]; then level=soft
  fi
  echo "spent: $spent"; echo "soft: $soft"; echo "hard: $hard"; echo "level: $level"
}

cmd_budget() {
  local run="${1:-}" size="${2:-}" soft="${3:-}" hard="${4:-}" state
  state=$(state_of "$run")
  case "$size" in S|M|L) ;; *) die "usage: budget RUN_DIR S|M|L [SOFT HARD]" ;; esac
  if [ -n "$soft" ] || [ -n "$hard" ]; then
    is_number "$soft" && is_number "$hard" || die "SOFT and HARD must be whole numbers"
  else
    soft=$(resolve_budget "$run" "$size" soft)
    hard=$(resolve_budget "$run" "$size" hard)
  fi
  [ "$soft" -le "$hard" ] || die "soft budget ($soft) is above hard budget ($hard)"
  table_set "$state" "## Budget" "Soft budget" "$soft"
  table_set "$state" "## Budget" "Hard budget" "$hard"
  budget_check "$state"
}

cmd_ack_soft() {
  local state; state=$(state_of "${1:-}")
  table_set "$state" "## Budget" "Soft budget acknowledged" "yes"
  budget_check "$state"
}

cmd_check() {
  budget_check "$(state_of "${1:-}")"
}

# Print one TSV line per API request: message id, model, first epoch, last epoch, in, cache write,
# cache read, out. Transcripts repeat a request once per content block, so group by message id.
transcript_requests() {
  if command -v jq >/dev/null 2>&1; then
    jq -rs '
      def epoch: sub("\\.[0-9]+"; "") | sub("Z$"; "Z") | fromdateiso8601;
      [ .[] | select(.type == "assistant" and .message.id != null and .message.usage != null) ]
      | group_by(.message.id)[]
      | [ .[0].message.id,
          (.[-1].message.model // "?"),
          (map(.timestamp | epoch) | min),
          (map(.timestamp | epoch) | max),
          (.[-1].message.usage.input_tokens // 0),
          (.[-1].message.usage.cache_creation_input_tokens // 0),
          (.[-1].message.usage.cache_read_input_tokens // 0),
          (map(.message.usage.output_tokens // 0) | max) ]
      | @tsv' "$1"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -I - "$1" <<'PY'
import json, sys
from datetime import datetime
reqs = {}
order = []
for line in open(sys.argv[1], encoding="utf-8"):
    try:
        d = json.loads(line)
    except ValueError:
        continue
    m = d.get("message") or {}
    if d.get("type") != "assistant" or not m.get("id") or not m.get("usage"):
        continue
    ts = datetime.fromisoformat(d["timestamp"].replace("Z", "+00:00")).timestamp()
    r = reqs.get(m["id"])
    if r is None:
        r = reqs[m["id"]] = {"t0": ts, "t1": ts, "out": 0}
        order.append(m["id"])
    u = m["usage"]
    r.update(model=m.get("model") or "?", t1=max(r["t1"], ts), t0=min(r["t0"], ts),
             inp=u.get("input_tokens") or 0, cw=u.get("cache_creation_input_tokens") or 0,
             cr=u.get("cache_read_input_tokens") or 0, out=max(r["out"], u.get("output_tokens") or 0))
for i in order:
    r = reqs[i]
    print("\t".join(str(x) for x in (i, r["model"], int(r["t0"]), int(r["t1"]), r["inp"], r["cw"], r["cr"], r["out"])))
PY
  else
    die "usage needs jq or python3"
  fi
}

cmd_usage() {
  local run="${1:-}" id="${2:-}" agent="${3:-}" step="${4:-}" round="${5:-}" status="${6:-}" state
  state=$(state_of "$run")
  [ -n "$id" ] && [ -n "$agent" ] && [ -n "$step" ] && [ -n "$status" ] || \
    die "usage: usage RUN_DIR AGENT_ID AGENT STEP ROUND STATUS"
  case "$id" in *[!A-Za-z0-9_-]*) die "bad agent id: $id" ;; esac
  [ -n "$round" ] || round=0

  local transcript="" f
  for f in "$CFG"/projects/*/*/subagents/agent-"$id".jsonl; do
    [ -f "$f" ] && transcript="$f"
  done

  local seen_dir="$run/.usage" tokens="?" duration="?" model="?"
  mkdir -p "$seen_dir"
  if [ -n "$transcript" ]; then
    local seen="$seen_dir/$id.seen" result
    touch "$seen"
    result=$(transcript_requests "$transcript" | awk -F'\t' -v seen="$seen" '
      BEGIN { while ((getline l < seen) > 0) done[l] = 1 }
      !($1 in done) {
        n++; model = $2
        if (t0 == "" || $3 < t0) t0 = $3
        if ($4 > t1) t1 = $4
        tok += $5 + 1.25 * $6 + 0.1 * $7 + 5 * $8
        print $1 >> seen
      }
      END {
        d = (n ? t1 - t0 : 0)
        printf "%d\t%dm%02ds\t%s\t%d\n", tok + 0.5, int(d / 60), d % 60, (model == "" ? "?" : model), n
      }')
    tokens=$(printf '%s' "$result" | cut -f1)
    duration=$(printf '%s' "$result" | cut -f2)
    model=$(printf '%s' "$result" | cut -f3)
  else
    echo "warning: no transcript found for agent $id under $CFG/projects; tokens not counted" >&2
  fi

  local n spent
  n=$(( $(table_rows "$state" "## Usage log" "#") + 1 ))
  table_add "$state" "## Usage log" "#" \
    "| $n | $(date +%H:%M) | $agent | $id | $step | $model | $tokens | $duration | $round | $status |"
  spent=$(table_get "$state" "## Budget" "Spent so far")
  is_number "$spent" || spent=0
  is_number "$tokens" && spent=$((spent + tokens))
  table_set "$state" "## Budget" "Spent so far" "$spent"

  echo "tokens: $tokens"
  echo "duration: $duration"
  echo "model: $model"
  budget_check "$state"
}

cmd_rework() {
  local run="${1:-}" task="${2:-}" force="${3:-}" state rounds total
  state=$(state_of "$run")
  [ -n "$task" ] || die "usage: rework RUN_DIR TASK [--force]"
  rounds=$(table_get "$state" "## Rework counters" "$task")
  total=$(table_get "$state" "## Rework counters" "**Run total**")
  is_number "$total" || total=0
  if ! is_number "$rounds"; then
    rounds=0
    table_add "$state" "## Rework counters" "Task" "| $task | 0 |" "**Run total**"
  fi
  if [ "$force" != --force ]; then
    if [ "$rounds" -ge "$TASK_CAP" ]; then
      echo "task: $task rounds: $rounds/$TASK_CAP run: $total/$RUN_CAP cap: task"; exit 3
    fi
    if [ "$total" -ge "$RUN_CAP" ]; then
      echo "task: $task rounds: $rounds/$TASK_CAP run: $total/$RUN_CAP cap: run"; exit 3
    fi
  fi
  rounds=$((rounds + 1)); total=$((total + 1))
  table_set "$state" "## Rework counters" "$task" "$rounds"
  table_set "$state" "## Rework counters" "**Run total**" "$total"
  echo "task: $task rounds: $rounds/$TASK_CAP run: $total/$RUN_CAP cap: ok"
}

cmd="${1:-}"; shift || true
case "$cmd" in
  new) cmd_new "$@" ;;
  files) cmd_files "$@" ;;
  active) cmd_active "$@" ;;
  budget) cmd_budget "$@" ;;
  check) cmd_check "$@" ;;
  ack-soft) cmd_ack_soft "$@" ;;
  usage) cmd_usage "$@" ;;
  rework) cmd_rework "$@" ;;
  *) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
