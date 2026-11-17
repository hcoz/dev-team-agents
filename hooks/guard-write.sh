#!/usr/bin/env bash
# guard-write.sh: PreToolUse hook that limits a dev-team role's file writes to the paths it owns.
#
#   guard-write.sh <role>        role: orchestrator | ba | architect | developer | tester
#
# Wired in each role's agent frontmatter for Write|Edit|MultiEdit|NotebookEdit, with
# onFailure: block. Reads the hook JSON on stdin. An owned path gets an explicit "allow"
# (no permission prompt). Any other path is denied with exit 2 and a reason on stderr.
#
# Allowed paths (P = project root, W = any linked git worktree of P, never the main checkout):
#   all roles   P/.claude/agent-memory/<role>/**  and  <cwd>/.claude/agent-memory/<role>/**
#   orchestrator P/.team/** ; ~/.claude/dev-team/playbooks/*.md ; ~/.claude/agent-memory/orchestrator/**
#   ba          P/.team/runs/<run-id>/requirements.md
#   architect   P/.team/{project-profile,stack-decision,roadmap}.md
#               P/.team/runs/<run-id>/{requirements,design,tasks}.md, P/.team/runs/<run-id>/logs/**
#   developer   W/** except W/.git and W/.team/**
#   tester      P/.team/runs/<run-id>/test-report.md, P/.team/runs/<run-id>/logs/**,
#               test files in W (see is_test_path)
#
# P is $CLAUDE_PROJECT_DIR, else the hook's cwd. Writes through Bash are not covered here
# (see guard-bash.sh). Default is deny: the script only exits 0 on an explicit allow.
# Works with macOS bash 3.2. Needs jq or python3 to read the hook input.

set -u
set -f
export LC_ALL=C

ROLE="${1:-}"

deny() {
  echo "guard-write ($ROLE): blocked. $*" >&2
  exit 2
}

allow() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"guard-write: %s owns this path"}}\n' "$ROLE"
  exit 0
}

case "$ROLE" in
  orchestrator|ba|architect|developer|tester) ;;
  *) deny "Unknown role '${ROLE}'. Usage: guard-write.sh orchestrator|ba|architect|developer|tester" ;;
esac

INPUT=$(cat)

# Print one field of the hook input: cwd, or the target path of a file tool.
field() {
  if command -v jq >/dev/null 2>&1; then
    case "$1" in
      cwd)  printf '%s' "$INPUT" | jq -r '.cwd // ""' ;;
      path) printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' ;;
    esac
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$INPUT" | python3 -I -c '
import json, sys
d = json.load(sys.stdin)
t = d.get("tool_input") or {}
v = d.get("cwd") if sys.argv[1] == "cwd" else (t.get("file_path") or t.get("notebook_path"))
print(v or "", end="")
' "$1"
  else
    return 1
  fi
}

CWD=$(field cwd) || deny "Neither jq nor python3 is available to read the hook input."
TARGET=$(field path) || deny "Could not parse the hook input."
[ -n "$TARGET" ] || deny "No file path in the tool input."
[ -n "$CWD" ] || CWD=$(pwd -P)

# Lexically normalize an absolute path: drop '.', '//' and resolve '..'.
normalize() {
  local IFS=/ seg out="" n=0
  local -a parts=()
  for seg in $1; do
    case "$seg" in
      ''|.) ;;
      ..) if [ "$n" -gt 0 ]; then n=$((n - 1)); unset "parts[$n]"; fi ;;
      *) parts[$n]="$seg"; n=$((n + 1)) ;;
    esac
  done
  local i=0
  while [ "$i" -lt "$n" ]; do out="$out/${parts[$i]}"; i=$((i + 1)); done
  printf '%s' "${out:-/}"
}

# Physical path: resolve symlinks in the deepest existing ancestor, keep the rest as is.
physical() {
  local p rest="" base
  p=$(normalize "$1")
  while [ ! -d "$p" ]; do
    base="${p##*/}"
    rest="/$base$rest"
    p="${p%/*}"
    [ -n "$p" ] || p=/
  done
  p=$(cd -P "$p" 2>/dev/null && pwd -P) || return 1
  [ "$p" = / ] && p=""
  printf '%s%s' "$p" "$rest"
}

case "$TARGET" in
  /*) ;;
  *) TARGET="$CWD/$TARGET" ;;
esac
[ -L "$TARGET" ] && deny "Refusing to write through a symlink: $TARGET"
TARGET=$(physical "$TARGET") || deny "Cannot resolve path: $TARGET"
CWD=$(physical "$CWD") || deny "Cannot resolve cwd: $CWD"
PROJECT=$(physical "${CLAUDE_PROJECT_DIR:-$CWD}") || deny "Cannot resolve project dir."

# Print the part of $1 below directory $2, or fail if $1 is not inside $2.
below() {
  case "$1" in
    "$2"/*) printf '%s' "${1#"$2"/}" ;;
    *) return 1 ;;
  esac
}

# Linked worktrees of the project (main checkout excluded), deepest path first.
linked_worktrees() {
  local line first=1
  git -C "$PROJECT" worktree list --porcelain 2>/dev/null | while IFS= read -r line; do
    case "$line" in
      "worktree "*)
        if [ "$first" = 1 ]; then first=0; continue; fi
        physical "${line#worktree }" && echo
        ;;
    esac
  done | awk '{ print length($0) "\t" $0 }' | sort -rn | cut -f2-
}

# Is the path (relative to a worktree root) a test file? Heuristic, stack-agnostic.
is_test_path() {
  local rel="$1" dir base seg
  base="${rel##*/}"
  case "$base" in
    test_*|*_test.*|*_tests.*|*.test.*|*.spec.*|*_spec.*|*Test.*|*Tests.*|*IT.java|*IT.kt|conftest.py|*.snap) return 0 ;;
  esac
  case "$rel" in */*) dir="${rel%/*}" ;; *) dir="" ;; esac
  local IFS=/
  for seg in $dir; do
    case "$seg" in
      test|tests|__tests__|spec|specs|e2e|testing|__mocks__|testdata|fixtures|__fixtures__|cypress|playwright) return 0 ;;
    esac
  done
  return 1
}

# Own agent memory.
for root in "$PROJECT" "$CWD"; do
  below "$TARGET" "$root/.claude/agent-memory/$ROLE" >/dev/null && allow
done

# Orchestrator: user-level knowledge (playbooks, its own user memory).
if [ "$ROLE" = orchestrator ]; then
  CFG=$(physical "${CLAUDE_CONFIG_DIR:-$HOME/.claude}") || deny "Cannot resolve the Claude config dir."
  REL=$(below "$TARGET" "$CFG/dev-team/playbooks") && case "$REL" in */*) ;; *.md) allow ;; esac
  below "$TARGET" "$CFG/agent-memory/orchestrator" >/dev/null && allow
fi

# Writes inside a linked worktree (developer, tester).
WORKTREE=""
while IFS= read -r wt; do
  [ -n "$wt" ] || continue
  if below "$TARGET" "$wt" >/dev/null; then WORKTREE="$wt"; break; fi
done <<EOF
$(linked_worktrees)
EOF

if [ -n "$WORKTREE" ]; then
  REL=$(below "$TARGET" "$WORKTREE")
  case "$REL" in
    .git|.git/*|.team|.team/*) deny "$REL is team or git state, not code. Path: $TARGET" ;;
  esac
  case "$ROLE" in
    developer) allow ;;
    tester)
      is_test_path "$REL" && allow
      deny "The Tester may only add or change test files. $REL looks like production code: report it as a finding instead." ;;
    *) deny "The ${ROLE} never edits code. Write only your own .team/ files." ;;
  esac
fi

# Writes under the project's .team/ directory.
REL=$(below "$TARGET" "$PROJECT/.team") || {
  case "$ROLE" in
    developer) deny "The Developer writes only inside its isolated git worktree, never the main checkout. Path: $TARGET" ;;
    tester) deny "The Tester writes only test-report.md and logs in RUN_DIR, and test files in the Developer's worktree. Path: $TARGET" ;;
    orchestrator) deny "The Orchestrator never edits code or project files: it writes only under $PROJECT/.team/, playbooks and its own memory. Route code changes to the Developer. Path: $TARGET" ;;
    *) deny "The ${ROLE} writes only its own files under $PROJECT/.team/. Path: $TARGET" ;;
  esac
}

RUN_FILE=""
case "$REL" in
  runs/*/*)
    rest="${REL#runs/}"
    run_id="${rest%%/*}"
    RUN_FILE="${rest#*/}"
    [ -n "$run_id" ] && [ "$run_id" != . ] || RUN_FILE=""
    ;;
esac

case "$ROLE" in
  orchestrator)
    allow ;;
  ba)
    [ "$RUN_FILE" = requirements.md ] && allow ;;
  architect)
    case "$REL" in project-profile.md|stack-decision.md|roadmap.md) allow ;; esac
    case "$RUN_FILE" in requirements.md|design.md|tasks.md|logs/?*) allow ;; esac ;;
  tester)
    case "$RUN_FILE" in test-report.md|logs/?*) allow ;; esac ;;
esac

deny "The ${ROLE} does not own .team/$REL. Ask the Orchestrator to route the change (team-handoff §2)."
