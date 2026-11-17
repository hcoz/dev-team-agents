#!/usr/bin/env bash
# guard-bash.sh: PreToolUse hook that blocks destructive or outward-facing shell commands for a
# dev-team role, and asks the owner about borderline ones.
#
#   guard-bash.sh <role>        role: orchestrator | ba | architect | developer | tester
#
# Wired in each role's agent frontmatter for Bash, with onFailure: block. Reads the hook JSON on
# stdin and checks tool_input.command:
#   deny  -> exit 2, reason on stderr (the agent sees it)
#   ask   -> JSON permissionDecision "ask" (the owner sees the reason in the prompt)
#   other -> exit 0 without output: the normal permission flow decides
#
# The check is text-based and conservative: a match anywhere in the command counts, including in
# quoted strings. It is a safety net, not a sandbox: the agents' prompts carry the same rules.
# Works with macOS bash 3.2. Needs jq or python3 to read the hook input.

set -u
set -f
export LC_ALL=C

ROLE="${1:-}"

deny() {
  echo "guard-bash ($ROLE): blocked. $*" >&2
  exit 2
}

ask() {
  local reason="guard-bash ($ROLE): $*"
  reason=$(printf '%s' "$reason" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$reason"
  exit 0
}

case "$ROLE" in
  orchestrator|ba|architect|developer|tester) ;;
  *) deny "Unknown role '${ROLE}'. Usage: guard-bash.sh orchestrator|ba|architect|developer|tester" ;;
esac

INPUT=$(cat)
# Opt-in trace for debugging and false-positive reviews: one JSON line per call.
if [ -n "${DEV_TEAM_HOOK_LOG:-}" ]; then
  printf '{"guard":"%s","role":"%s","input":%s}\n' "${0##*/}" "$ROLE" "$INPUT" >> "$DEV_TEAM_HOOK_LOG" 2>/dev/null || true
fi

# A session started with `claude --agent orchestrator` also runs the orchestrator's hooks for its
# subagents' tool calls. Those calls carry agent_id and agent_type. Each team role has its own
# guard, so the orchestrator's guard stays out of their calls (no output: no decision).
if [ "$ROLE" = orchestrator ]; then
  json_top() {
    if command -v jq >/dev/null 2>&1; then printf '%s' "$INPUT" | jq -r --arg k "$1" '.[$k] // ""'
    else printf '%s' "$INPUT" | python3 -I -c 'import json, sys; print(json.load(sys.stdin).get(sys.argv[1]) or "", end="")' "$1"
    fi
  }
  if [ -n "$(json_top agent_id 2>/dev/null)" ]; then
    case "$(json_top agent_type 2>/dev/null)" in ba|architect|developer|tester) exit 0 ;; esac
  fi
fi
field() {
  if command -v jq >/dev/null 2>&1; then
    case "$1" in
      cmd) printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' ;;
      cwd) printf '%s' "$INPUT" | jq -r '.cwd // ""' ;;
    esac
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$INPUT" | python3 -I -c '
import json, sys
d = json.load(sys.stdin)
v = (d.get("tool_input") or {}).get("command") if sys.argv[1] == "cmd" else d.get("cwd")
print(v or "", end="")
' "$1"
  else
    return 1
  fi
}
CMD=$(field cmd) || deny "Neither jq nor python3 could read the hook input."
CWD=$(field cwd) || CWD=""
[ -n "$CMD" ] || exit 0
[ -n "$CWD" ] || CWD=$(pwd)
PROJECT="${CLAUDE_PROJECT_DIR:-$CWD}"

# has REGEX: does the whole command match (extended regex)?
has() { printf '%s' "$CMD" | grep -Eq -- "$1"; }

# Print the command split into simple segments (at && || ; | $( and backticks), one per line.
segments() {
  printf '%s\n' "$CMD" | sed -E 's/(&&|\|\||;|\||\$\(|`)/\
/g'
}

B='(^|[^A-Za-z0-9_./-])'   # start of a word
E='([^A-Za-z0-9_-]|$)'     # end of a word

# --- Whole-command checks ------------------------------------------------------------------------

has "(curl|wget)${E}[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z|da|k)?sh${E}" \
  && deny "Piping a download into a shell. Download, read and run it as separate, reviewed steps."
has ":\(\)[[:space:]]*\{" && deny "Fork bomb."
has "${B}(sudo|doas|su)${E}" && deny "No privilege escalation: the team never needs root."
has "${B}(mkfs(\.[a-z0-9]+)?|diskutil|shred|fdisk|wipefs)${E}" && deny "Disk-level command."
has "${B}dd${E}.*of=/dev/" && deny "dd onto a device."
has "${B}(shutdown|reboot|halt|launchctl|systemctl)${E}" && deny "System service or power command."
has "${B}chmod${E}[^|;&]*-R[^|;&]*777|${B}chown${E}[^|;&]*-R" && deny "Recursive permission or ownership change."
has "${B}crontab${E}" && deny "Scheduling jobs on this machine."

# Recursive rm of a dangerous target: / ~ $HOME .. * or any absolute path outside a project dir.
A='[[:space:]]([^|;&]*[[:space:]])?'   # a space, then any further arguments of the same command
if has "${B}rm${A}-[A-Za-z]*[rR]"; then
  has "${B}rm${A}(/|/\*|~|~/|~/\*|\\\$HOME|\"\\\$HOME\"|\\\$HOME/\*|\.\.|\.\./?\*?|\*|\.|\./\*)([[:space:]]|;|&|\||$)" \
    && deny "Recursive rm of /, ~, \$HOME, .., . or *."
  for a in $(printf '%s' "$CMD" | grep -Eo "${B}rm${E}[^|;&]*" | tr -d "\"'"); do
    case "$a" in
      rm|-*) ;;
      /tmp/*|/private/tmp/*|/var/folders/*|"$PROJECT"/*|"$CWD"/*) ;;
      /*|~*|'$HOME'*) ask "Recursive rm outside the project: $a" ;;
    esac
  done
fi

# Secrets: reading .env files (not .env.example and friends), SSH/cloud credentials, the environment.
ENV_RE="(^|[[:space:]/'\"=<])\.env(\.[A-Za-z0-9_-]+)?([[:space:]'\";|&)>]|$)"
while IFS= read -r seg; do
  printf '%s' "$seg" | grep -Eo "$ENV_RE" | grep -Evq '\.env\.(example|sample|template|dist|defaults)' || continue
  first=$(printf '%s' "$seg" | awk '{ for (i = 1; i <= NF; i++) if ($i !~ /=/ && $i != "(" && $i != "!") { print $i; exit } }')
  case "${first##*/}" in
    ls|test|'['|'[['|stat|find|git) ;;
    *) deny "Never read or print .env files: note only that they exist (see project-discovery)." ;;
  esac
done <<EOF
$(segments)
EOF
has "(~|\\\$HOME|/Users/[^/]+|/home/[^/]+)/\.(ssh|aws|gnupg|kube|docker/config\.json|netrc|npmrc|pypirc)" \
  && deny "Credential files are off limits."
has "(^|[;&|][[:space:]]*)(printenv|env|export -p|set)[[:space:]]*($|[;&|])" \
  && deny "Dumping the environment can expose secrets. Print only the variable names you need."

# Publishing, deploying and remote infrastructure.
has "${B}(npm|pnpm|yarn|bun)[[:space:]]+(publish|deprecate|unpublish|dist-tag|owner)${E}" && deny "Publishing a package."
has "${B}(cargo|gem|poetry|twine|uv|flit|hatch|dotnet[[:space:]]+nuget|mvn|gradle)[[:space:]]+([^|;&]*[[:space:]])?(publish|push|upload|deploy)${E}" \
  && deny "Publishing or deploying an artifact."
has "${B}(docker|podman)[[:space:]]+(push|login)${E}" && deny "Pushing to a registry."
has "${B}(kubectl|helm|terraform|tofu|pulumi|cdk|serverless|sls|vercel|netlify|fly|flyctl|heroku|firebase|wrangler|eb|sam)${A}(apply|delete|destroy|up|deploy|install|upgrade|uninstall|rollback|replace|patch|scale|publish|push|create|rm|--prod)${E}" \
  && deny "Changing remote infrastructure or deploying."
has "${B}gh${A}(pr|release|repo|issue|secret|workflow|api)[[:space:]]+(create|merge|delete|edit|close|reopen|comment|run|set|upload|-X|--method)${E}" \
  && deny "Changing GitHub state. Only the owner does that."
has "${B}(aws|gcloud|az|doctl|oci)${E}" && ask "Cloud CLI command. Approve only if it is read-only and expected."

# Global or system-wide installs.
has "${B}(npm|pnpm|yarn|bun)${E}[^|;&]*([[:space:]]-g|[[:space:]]--global|[[:space:]]global[[:space:]])" && deny "Global package install."
has "${B}(brew|apt|apt-get|yum|dnf|pacman|port|snap|choco|winget)[[:space:]]+(install|upgrade|remove|uninstall|update)${E}" \
  && ask "System package manager. The team should use only the project's own tooling."
has "${B}pip3?[[:space:]]+install${E}[^|;&]*--user|${B}pip3?[[:space:]]+install${E}[^|;&]*--break-system-packages" \
  && deny "User or system pip install. Use the project's environment."

# Docker cleanup that reaches beyond the project.
has "${B}(docker|podman)[[:space:]]+(system|volume|image|container|network)[[:space:]]+prune${E}" && deny "Docker prune affects other projects."

# --- git -----------------------------------------------------------------------------------------

# Print each git subcommand in the command (skipping global options such as -C <dir> and -c k=v),
# one per line as "<subcommand> <rest of segment>".
git_calls() {
  segments | awk '
    {
      n = split($0, w, /[[:space:]]+/); i = 1
      while (i <= n && (w[i] == "" || w[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/ || w[i] == "(" || w[i] == "{" || w[i] == "!" || w[i] == "command" || w[i] == "exec" || w[i] == "nohup" || w[i] == "time")) i++
      if (w[i] == "timeout") { i++; while (i <= n && w[i] ~ /^-/) i++; i++ }
      if (w[i] == "env") { i++; while (i <= n && (w[i] ~ /^-/ || w[i] ~ /=/)) i++ }
      if (w[i] !~ /(^|\/)git$/) next
      i++
      while (i <= n) {
        if (w[i] == "-C" || w[i] == "-c" || w[i] == "--git-dir" || w[i] == "--work-tree" || w[i] == "--namespace") { i += 2; continue }
        if (w[i] ~ /^-/) { i++; continue }
        break
      }
      if (i > n) next
      out = w[i]
      for (j = i + 1; j <= n; j++) out = out " " w[j]
      print out
    }'
}

while IFS= read -r call; do
  [ -n "$call" ] || continue
  sub="${call%% *}"
  args=" ${call#"$sub"} "
  [ "$call" = "$sub" ] && args=" "
  case "$sub" in
    push) deny "git push is the owner's job. Never push." ;;
    filter-branch|filter-repo|replace|update-ref|reflog|gc|prune|fsck) deny "git $sub rewrites or prunes history." ;;
    remote)
      case "$args" in *" add "*|*" remove "*|*" rm "*|*" set-url "*|*" rename "*) deny "Changing git remotes." ;; esac ;;
    config)
      case "$args" in *" --get"*|*" -l "*|*" --list "*) ;; *) deny "Changing git config." ;; esac ;;
    clean)
      case "$args" in *" -n"*|*" --dry-run"*) ;; *) deny "git clean deletes untracked files. List them with git clean -n and ask instead." ;; esac ;;
    rebase) deny "git rebase rewrites history." ;;
  esac
  case "$args" in *" --force"*|*" -f "*|*" --force-with-lease"*)
    case "$sub" in add|rm|mv|tag|checkout|switch|branch|worktree|clean|reset) deny "Forced git $sub." ;; esac ;;
  esac

  case "$ROLE" in
    orchestrator)
      case "$sub" in
        reset) case "$args" in *" --hard"*|*" --merge"*|*" --keep"*) deny "git reset --hard discards work." ;; esac ;;
        branch) case "$args" in *" -D "*|*" --delete --force"*) deny "Deleting an unmerged branch. Use git branch -d." ;; esac ;;
        checkout|restore) case "$args" in *" . "*|*" -- . "*|*" :/ "*) deny "Discarding all changes." ;; esac ;;
        stash) case "$args" in *" drop"*|*" clear"*) deny "Dropping stashed work." ;; esac ;;
        merge) case "$args" in *" --abort "*|*" --no-ff "*|*" --ff-only "*) ;; *) ask "git merge without --no-ff or --ff-only. Merges happen only after Gate 3." ;; esac ;;
        tag) deny "Tags are the owner's job." ;;
      esac ;;
    architect|ba)
      case "$sub" in
        status|log|diff|show|ls-files|ls-tree|rev-parse|branch|blame|grep|describe|shortlog|cat-file|rev-list|merge-base|symbolic-ref|name-rev|for-each-ref|check-ignore|config|remote|worktree)
          case "$sub $args" in "branch "*" -"[dDmMcC]" "*|"branch "*" --delete"*|"branch "*" --move"*|"worktree "*" add "*|"worktree "*" remove "*|"worktree "*" prune "*)
            deny "The ${ROLE} only reads git state." ;; esac ;;
        *) deny "The ${ROLE} only reads git state (git $sub is not read-only)." ;;
      esac ;;
    developer)
      case "$sub" in
        reset) case "$args" in *" --hard"*|*" --merge"*|*" --keep"*) deny "git reset --hard discards work. Revert with new commits or ask." ;; esac ;;
        merge) case "$args" in *" --ff-only "*) ;; *) deny "The Developer only fast-forwards (git merge --ff-only START_FROM)." ;; esac ;;
        branch) case "$args" in *" -d "*|*" -D "*|*" --delete"*|*" -m "*|*" -M "*|*" --move"*) deny "Do not delete or rename branches." ;; esac ;;
        checkout|switch)
          case "$args" in *" -- "*|*" -p "*|*" --patch "*) ;; *) deny "Stay on your branch: do not switch branches or check out other commits." ;; esac ;;
        restore) case "$args" in *" . "*|*" :/ "*) deny "Discarding all changes. Restore single files only." ;; esac ;;
        worktree|tag|stash) case "$sub $args" in "stash "*" list "*|"worktree "*" list "*) ;; *) deny "git $sub is not part of the Developer's job." ;; esac ;;
      esac ;;
    tester)
      case "$sub" in
        status|log|diff|show|ls-files|rev-parse|blame|grep|describe|cat-file|rev-list|merge-base|add|commit) ;;
        branch) case "$args" in *" -"[dDmMcC]" "*|*" --delete"*|*" --move"*|*" --copy"*|*" -f "*|*" --force"*) deny "The Tester does not change branches." ;; esac ;;
        *) deny "The Tester only reads git state and commits test files (git $sub is not allowed)." ;;
      esac
      case "$sub $args" in "commit "*" --amend"*) deny "Never amend: add a new test: commit." ;; esac ;;
  esac
done <<EOF
$(git_calls)
EOF

# --- Writes from the shell by roles that run in the main checkout ----------------------------------

# Is a path a log, temp or null target (the only places these roles may write from the shell)?
# Inside the project only RUN_DIR/logs counts, even when the project itself lives in a temp dir.
log_or_temp() {
  local p="$1"
  case "$p" in /tmp/*) p="/private$p" ;; esac
  case "$p" in
    /dev/null|/dev/stdout|/dev/stderr|'&'*) return 0 ;;
    *'/../'*|*'/..') return 1 ;;
    *'/.team/runs/'*/logs|*'/.team/runs/'*/logs/*|*'$RUN_DIR'*|*'${RUN_DIR}'*) return 0 ;;
    "$PROJECT_P"|"$PROJECT_P"/*|"$CWD_P"|"$CWD_P"/*) return 1 ;;
    /private/tmp/*|/var/folders/*|'$TMPDIR'*|'${TMPDIR'*) return 0 ;;
  esac
  return 1
}
PROJECT_P="$PROJECT"; case "$PROJECT_P" in /tmp/*) PROJECT_P="/private$PROJECT_P" ;; esac
CWD_P="$CWD"; case "$CWD_P" in /tmp/*) CWD_P="/private$CWD_P" ;; esac

case "$ROLE" in
  ba|architect|tester)
    # File-changing commands: acceptEdits would auto-approve them inside the project.
    while IFS= read -r seg; do
      set -- $seg
      while [ $# -gt 0 ]; do case "$1" in *=*|'('|'{'|'!'|command|exec) shift ;; *) break ;; esac; done
      [ $# -gt 0 ] || continue
      case "${1##*/}" in
        rm|rmdir|unlink|mv|cp|ln|touch|mkdir|chmod|chown|truncate|install|rsync|patch|tar|unzip)
          verb="${1##*/}"; shift
          for a in "$@"; do
            case "$a" in -*|'>'*|'2>'*|'&>'*|[0-9]'>'*) continue ;; esac
            a=$(printf '%s' "$a" | tr -d "\"'")
            log_or_temp "$a" || deny "$verb may touch only RUN_DIR/logs/ or a temp dir from the shell (not '$a'). Write your own files with Write or Edit."
          done ;;
      esac
    done <<SEGS
$(segments)
SEGS
    has "${B}(sed|perl|ruby)${A}-[A-Za-z]*i" \
      && deny "No in-place edits from the shell. Use Edit or Write, which are scoped to your files."
    # Redirect and tee targets must be logs, temp files or /dev/null.
    targets=$(
      printf '%s' "$CMD" | grep -Eo '(^|[^0-9&<>=-])>>?[[:space:]]*[^[:space:]&|;<>()]+' | sed -E 's/^[^>]?>>?[[:space:]]*//'
      printf '%s' "$CMD" | grep -Eo '(^|[[:space:]|])tee([[:space:]]+-a)?[[:space:]]+[^[:space:]&|;<>()]+' | sed -E 's/^.*tee([[:space:]]+-a)?[[:space:]]+//'
    )
    targets=$(printf '%s' "$targets" | tr -d "\"'")
    while IFS= read -r t; do
      [ -n "$t" ] || continue
      case "$t" in
        *) log_or_temp "$t" && continue
           deny "Shell output may go only to RUN_DIR/logs/, a temp dir or /dev/null (not '$t'). Write files with Write or Edit." ;;
      esac
    done <<EOF
$targets
EOF
    ;;
esac

# --- Auto-allow: the plain git steps a role needs ------------------------------------------------
# Claude Code asks before git writes, and before any git command that follows a `cd` into another
# directory (its hooks and config could be untrusted). A background subagent cannot ask, so the step
# would simply fail. This guard allows a short per-role list itself, scoped to the role, not to the
# whole session as a settings rule would be, and only in this project's own repository (the main
# checkout or one of its worktrees: same hooks and config). Only a plain chain qualifies: `cd <dir>`
# and git steps joined by &&, no pipes, redirects, substitutions or -C. Anything else: normal flow.
#   every role   read-only steps: status, diff, log, show, rev-parse, ls-files, merge-base, rev-list,
#                blame, branch --show-current, worktree list
#   developer  add, rm, mv, restore <files>, commit (no --amend), merge --ff-only; in a linked worktree
#   tester     add, commit (no --amend); in a linked worktree
#   orchestrator init, add, commit (no --amend), merge --no-ff|--ff-only|--abort, worktree remove,
#              branch -d; in the main checkout (the gates approve these steps)

allow_bash() {
  local reason="guard-bash: plain git step owned by the $ROLE"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"%s"}}\n' "$reason"
  exit 0
}

# Physical path of an existing directory, or fail.
dir_p() { (cd -P "$1" 2>/dev/null && pwd -P); }

# Is DIR the project's main checkout or one of its worktrees (the same repository)?
same_repo() {
  local common pcommon
  common=$(cd "$1" 2>/dev/null && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  pcommon=$(cd "$PROJECT" 2>/dev/null && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  [ "$(dir_p "$common")" = "$(dir_p "$pcommon")" ]
}

# May the role run git writes in DIR?
git_place_ok() {
  local dir="$1" common gitdir
  same_repo "$dir" || return 1
  common=$(cd "$dir" 2>/dev/null && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  gitdir=$(cd "$dir" 2>/dev/null && git rev-parse --absolute-git-dir 2>/dev/null) || return 1
  case "$ROLE" in
    developer|tester) [ "$(dir_p "$gitdir")" != "$(dir_p "$common")" ] ;;   # a linked worktree
    orchestrator) [ "$(dir_p "$dir")" = "$(dir_p "$PROJECT")" ] ;;          # the main checkout
    *) return 1 ;;
  esac
}

auto_allow() {
  local chain dir="$CWD" steps=0 seg sub rest
  # Substitutions are never plain, not even inside double quotes.
  printf '%s' "$CMD" | grep -Eq '`|\$\(|\$\{' && return 1
  # Operators count only outside quotes: a commit message may hold < > ; | or line breaks.
  # Inside quotes they become "_" and the quote marks go; a quote left open fails the check.
  local plain
  plain=$(printf '%s' "$CMD" | awk '
    { s = s (NR > 1 ? "\n" : "") $0 }
    END {
      q = ""; out = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (q == "") {
          if (c == "\047" || c == "\"") q = c; else out = out c
        } else if (q == "\"" && c == "\\") {
          i++; out = out "_"
        } else if (c == q) {
          q = ""
        } else {
          out = out (index("|;<>&\n", c) ? "_" : c)
        }
      }
      if (q != "") out = out ";"
      printf "%s", out
    }')
  case "$plain" in *"
"*) return 1 ;; esac
  chain=$(printf '%s' "$plain" | awk '{ gsub(/&&/, "\n"); print }')
  printf '%s' "$chain" | grep -Eq "[|;<>&]|^[[:space:]]*$" && return 1
  while IFS= read -r seg; do
    seg=$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
    [ -n "$seg" ] || return 1
    set -- $seg
    case "$1" in
      cd)
        [ $# -eq 2 ] || return 1
        dir="$2"
        case "$dir" in /*) ;; *) dir="$CWD/$dir" ;; esac
        [ -d "$dir" ] || return 1 ;;
      git)
        shift; sub="${1:-}"; [ -n "$sub" ] && shift; rest=" $* "
        case "$rest" in *" -C "*|*" -c "*|*" --git-dir"*|*" --work-tree"*|*" --amend"*|*" --force"*|*" -f "*|*" --no-verify"*) return 1 ;; esac
        steps=1
        case "$sub:$rest" in
          status:*|diff:*|log:*|show:*|rev-parse:*|ls-files:*|merge-base:*|rev-list:*|blame:*|"branch: --show-current "|"worktree: list "*)
            same_repo "$dir" || return 1
            continue ;;
        esac
        case "$ROLE:$sub" in
          developer:add|developer:rm|developer:mv|developer:restore|developer:commit|tester:add|tester:commit|orchestrator:add|orchestrator:commit|orchestrator:init) ;;
          developer:merge) case "$rest" in " --ff-only "*) ;; *) return 1 ;; esac ;;
          orchestrator:merge) case "$rest" in " --no-ff "*|" --ff-only "*|" --abort ") ;; *) return 1 ;; esac ;;
          orchestrator:worktree) case "$rest" in " remove "*) ;; *) return 1 ;; esac ;;
          orchestrator:branch) case "$rest" in " -d "*) ;; *) return 1 ;; esac ;;
          *) return 1 ;;
        esac
        if [ "$sub" = init ]; then
          [ "$(dir_p "$dir")" = "$(dir_p "$PROJECT")" ] || return 1
        else
          git_place_ok "$dir" || return 1
        fi ;;
      *) return 1 ;;
    esac
  done <<CHAIN
$chain
CHAIN
  [ "$steps" = 1 ]
}

auto_allow && allow_bash

exit 0
