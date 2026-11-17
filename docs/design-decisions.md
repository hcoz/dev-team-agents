# Design decisions

This file records why dev-team-agents is built the way it is: the decision, the alternatives that were rejected, and the consequences, with evidence from the Phase 6 dry-runs where there is any. The one-line summary of each decision is in [implementation-plan.md §7](implementation-plan.md#7-key-decisions). The figures are in [e2e-dry-run-notes.md](e2e-dry-run-notes.md).

Status as of v0.1.0 (2026-11-17). When a decision changes, edit its entry and add a line to its *History*. Do not delete it.

| # | Decision | Area |
|---|---|---|
| [DD-1](#dd-1-subagents-and-an-orchestrator-not-agent-teams) | Subagents and an Orchestrator, not agent teams | Architecture |
| [DD-2](#dd-2-state-lives-on-disk-replies-are-summaries) | State lives on disk; replies are summaries | Architecture |
| [DD-3](#dd-3-one-project-profile-for-both-modes) | One project profile for both modes | Architecture |
| [DD-4](#dd-4-greenfield-requirements-before-stack-walking-skeleton-first) | Greenfield: requirements before stack, walking skeleton first | Workflow |
| [DD-5](#dd-5-humans-decide-at-gates-routed-through-the-orchestrator) | Humans decide at gates, routed through the Orchestrator | Workflow |
| [DD-6](#dd-6-requests-are-sized-s--m--l) | Requests are sized S / M / L | Workflow · cost |
| [DD-7](#dd-7-orchestrator-relayed-rework-with-caps) | Orchestrator-relayed rework, with caps | Workflow |
| [DD-8](#dd-8-the-developer-works-in-a-worktree-only-the-orchestrator-merges) | The Developer works in a worktree; only the Orchestrator merges | Code and git |
| [DD-9](#dd-9-least-privilege-through-per-role-hooks-not-settings-rules) | Least privilege through per-role hooks, not settings rules | Safety |
| [DD-10](#dd-10-hooks-grant-the-approvals-background-agents-cannot-ask-for) | Hooks grant the approvals background agents cannot ask for | Safety |
| [DD-11](#dd-11-plain-shell-commands-only) | Plain shell commands only | Safety · reliability |
| [DD-12](#dd-12-deterministic-scripts-for-everything-that-is-counted) | Deterministic scripts for everything that is counted | Reliability |
| [DD-13](#dd-13-model-tier-per-role) | Model tier per role | Cost |
| [DD-14](#dd-14-measured-spend-orchestrator-included-with-soft-and-hard-budgets) | Measured spend, Orchestrator included, with soft and hard budgets | Cost |
| [DD-15](#dd-15-learning-is-explicit-layered-and-approved) | Learning is explicit, layered and approved | Learning |
| [DD-16](#dd-16-fingerprints-and-incremental-re-discovery) | Fingerprints and incremental re-discovery | Learning · cost |
| [DD-17](#dd-17-user-level-plain-files-symlinked-not-a-plugin) | User-level plain files, symlinked, not a plugin | Distribution |

---

## Architecture

### DD-1. Subagents and an Orchestrator, not agent teams

**Decision.** The main session runs the `orchestrator` agent (`claude --agent orchestrator`). It calls `ba`, `architect`, `developer` and `tester` as subagents, one at a time, and relays everything between them.

**Why.** Subagents are cheaper and more predictable than Claude Code's experimental agent teams. Each runs in its own context, reports only to its caller and ends with a status line, so the flow is a state machine the Orchestrator can drive and log. Peer-to-peer messaging would make the order of work, the rework count and the spend harder to bound.

**Rejected.**
- *Agent teams* (teammates messaging each other through a shared task list): experimental, higher token cost, and harder to gate.
- *One big agent with role prompts*: one long context, no least privilege per role, no worktree isolation for the code.

**Consequences.** Every hand-off costs an Orchestrator turn, and the Orchestrator's context grows with each one (see DD-14). Agents run one after another, never in parallel. Agent teams stay a Phase 8 option, to be used only if the relayed tester ⇄ developer loop proves insufficient. Phase 6 gave no reason to switch: all rework loops converged, most at 0 rounds.

### DD-2. State lives on disk; replies are summaries

**Decision.** All hand-offs go through files in `<project>/.team/`. Each request gets its own run folder with a `state.md` that the Orchestrator alone writes. An agent's reply has three parts: a summary of at most ~10 lines, the paths of the files it wrote, and one status line (the *return contract*).

**Why.** Subagents have isolated contexts, so a fact that is not in a file is lost to the next role. Keeping full content out of replies keeps the long-lived Orchestrator context small. And a run that lives on disk survives a closed session.

**Rejected.** Passing content through the Orchestrator's prompts, which bloats its context and loses everything when the session ends.

**Consequences.** In Phase 6 a greenfield run was cut off by the account usage limit in the middle of a task. It resumed from `state.md` in a fresh session. Templates fix the structure of every file: agents fill in sections and never add or rename them, which keeps the Orchestrator's Grep-based briefs reliable.

### DD-3. One project profile for both modes

**Decision.** Greenfield and brownfield both produce `.team/project-profile.md`: the stack, the exact commands, the conventions and a fingerprint. Its `origin` is `decided` or `discovered`, and its `status` is `draft`, `planned` or `verified`. Once it is `verified`, the project is *established*, and every later run takes the same path. The mode is detected by `stack-scan.sh mode`, ambiguous directories are put to the owner, and the owner can always override.

**Why.** Agents should never guess build or test commands, and they should not need to know how a project started. One artifact read by every role gives one place to fix wrong knowledge.

**Rejected.** Separate greenfield and brownfield pipelines all the way through, which would mean two sets of prompts to maintain, drifting apart.

**Consequences.** In Phase 6, after M0 the greenfield project ran its next request as Established, with no discovery and no Gate 0. Stack-specific knowledge lives only in profiles and playbooks, never in agent prompts, so the core stays stack-agnostic.

## Workflow

### DD-4. Greenfield: requirements before stack, walking skeleton first

**Decision.** In greenfield, the BA's requirements (Gate 1) come before the stack (Gate 0). The Architect proposes 2–3 stacks with trade-offs and one recommendation, with versions checked against official sources. The owner decides. Scope is cut into milestones in `roadmap.md`. M0 is always a walking skeleton, and each run builds one milestone.

**Why.** A stack can only be judged against known requirements. The owner keeps the final say on something they will have to live with. One of the options is always the simplest stack that meets the requirements, which guards against over-engineering. Versions recalled from model memory go out of date, so they are checked. A walking skeleton proves the planned commands before any feature work depends on them.

**Rejected.**
- *Stack first*: it would be chosen without the constraints it must satisfy.
- *Architect picks silently*: the owner would only find out about the choice at the merge.
- *Whole product in one run*: an unbounded rework loop and an unreviewable diff.

**Consequences.** The profile stays `planned` until the Tester has run every command against the scaffold. Deviations are fixed by an Architect `profile-update` and shown at Gate 3. In Phase 6 the stack proposal used 13 web lookups, and M0 ended with 30 passing tests and a `verified` profile.

### DD-5. Humans decide at gates, routed through the Orchestrator

**Decision.** There are four gates: 0 Stack, 1 Requirements, 2 Design and 3 Merge. Agents decide everything else. When only the owner can decide, an agent returns `NEEDS_HUMAN: <question> Options: …`, and the Orchestrator asks and resumes the agent with the answer. When `AskUserQuestion` is unavailable (print mode), the Orchestrator writes the brief and numbered questions in its reply and ends its turn.

**Why.** `AskUserQuestion` is removed from subagents' tool pools, so only the main session can talk to the owner. Fixed gates keep the owner's effort predictable, and everything between gates stays automatic.

**Consequences.** S and M runs merge Gates 1 and 2 into one gate (DD-6). Gate 0 runs once per project, plus once whenever the profile goes stale. In Phase 6, scenarios 2–6 needed nothing from the owner beyond gate answers and agents' `NEEDS_HUMAN` questions. Interactive gates through `AskUserQuestion` are not yet validated.

### DD-6. Requests are sized S / M / L

**Decision.** The Orchestrator proposes a size, and the owner confirms it at the first gate.
- **S:** the Orchestrator writes a scope note, then Developer ⇄ Tester.
- **M:** the Architect writes requirements and design in one call.
- **L:** the full pipeline.

Agents may ask to upsize. They never upsize on their own.

**Why.** This is the biggest cost lever. A one-line fix should not pay for a BA, an Opus design call and three gates.

**Consequences.** In Phase 6 an established S run cost 12% of a brownfield L run counting subagents, and 18% including the Orchestrator, against a target of ≤ 25%. An upsize from M to L wasted one Opus design call (~171k): the price of starting small. Greenfield is L through M0.

### DD-7. Orchestrator-relayed rework, with caps

**Decision.** The Tester writes findings with stable IDs (`F1`, `F2` …) and returns `NEEDS_REWORK: developer — F1, F3`. The Orchestrator resumes the same Developer, which keeps its context, then the Tester re-checks only those IDs. The caps are 3 rounds per task and 8 per run, enforced by `run-state.sh rework`. When a cap is reached, the owner chooses: more rounds, less scope, or abort. When the Developer disputes a finding, the Orchestrator settles it if the acceptance criteria do, and otherwise asks the owner.

**Why.** Caps keep cost predictable and stop endless loops. Resuming is much cheaper than starting cold: in Phase 6, resuming a Developer cost 24k, against 50–130k for a fresh call.

**Consequences.** Targeted tests run per task, and the full suite runs once, on Haiku, before Gate 3. Fixes found by the full pass go to the last task's Developer, whose worktree holds the whole run.

## Code and git

### DD-8. The Developer works in a worktree; only the Orchestrator merges

**Decision.** The Developer runs with `isolation: worktree` and commits on its own branch. Each task gets a fresh Developer that starts from the previous task's head (`START_FROM`), and rework resumes the same Developer. The Tester works in that same worktree. It may add test files, committed as `test: …`, but never edits production code. After Gate 3, the Orchestrator alone merges the last branch with `--no-ff` in the main checkout, commits the knowledge files, and removes the worktrees and merged branches. Nobody pushes.

**Why.** The owner's checkout is never touched by unreviewed code. Starting each task's Developer fresh keeps its context small. The `START_FROM` chain makes the last branch contain the whole run, so there is one merge and the history stays linear.

**Rejected.**
- *One Developer for all tasks*: its context would grow across tasks.
- *One branch per task merged separately*: more merges, more conflicts, more gates.
- *Auto-push*: outward-facing and hard to undo.

**Consequences.** The target must be a git repo with at least one commit. The Orchestrator offers `git init` and an initial commit (greenfield: at Gate 0). Worktrees live in `<project>/.claude/worktrees/` and are kept out of `git status` through `.git/info/exclude`. The Orchestrator checks every reported head against `git rev-parse HEAD` in the worktree. Commits that are not recorded in `state.md` are never used.

## Safety and permissions

### DD-9. Least privilege through per-role hooks, not settings rules

**Decision.** Each agent's frontmatter wires `guard-write.sh <role>` and `guard-bash.sh <role>` as `PreToolUse` hooks with `onFailure: block`. `guard-write` allows exactly the paths a role owns and denies the rest. The BA and Architect write only under `.team/`, the Tester writes test files and its report, and the Developer writes only in its worktree. `guard-bash` denies push, history rewrites, publishing, deploys, privilege escalation and secret reads for every role, asks the owner about borderline commands, and limits shell writes per role. The settings snippet has **no deny rules**.

**Why.** User-level deny rules would also restrict the owner's own sessions. Hooks run only where they are wired. `onFailure: block` makes a crashing guard fail closed.

**Consequences.**
- **Hooks are inherited.** A session started with `claude --agent orchestrator` also runs the Orchestrator's hooks for its subagents' calls. Phase 6 found this when the Orchestrator's guard denied every Developer edit. The Orchestrator's guards now make no decision for calls that carry a team role's `agent_id`/`agent_type`, because those roles have their own guards.
- **Text matching is conservative.** The guards match command text: quoted strings are neutralized, and `$(…)`, backticks and unquoted operators are never allowed. They are a safety net behind the prompts, not a sandbox.
- **Version floor.** The guards need Claude Code ≥ 2.1.295 and the config dir at `~/.claude`.

### DD-10. Hooks grant the approvals background agents cannot ask for

**Decision.** The guard hooks return an explicit `allow` for the few actions a role needs and that the permission system would otherwise prompt for:
- the Developer and Tester: plain `git add`, `commit` and read-only git, in a linked worktree;
- the Orchestrator: `init`, `merge`, `worktree remove` and `branch -d`, in the main checkout;
- the Architect: web lookups, through `allow-web.sh`, capped at 15 per call.

The Architect, Developer and Tester run in `acceptEdits`, with their shell writes fenced by `guard-bash.sh`.

**Why.** Background subagents cannot show a permission prompt, so whatever needs approval is simply denied. Phase 6 found this on git commits, log redirects and every web lookup. Settings allow rules would grant the same rights to the owner's own sessions.

**Consequences.** After the fixes, a run hit 0–2 denials, all from the Orchestrator's first commands. Project commands (`npm ci`, `make test` …) still need one-time allow rules per project, and the README says so. The settings snippet adds the install's directories as `additionalDirectories`. In a symlink install it also adds the repo's real path, because permission checks resolve symlinks.

### DD-11. Plain shell commands only

**Decision.** Every role uses one command per Bash call, with literal absolute paths. No `$(…)`, backticks, `;` chains, loops, shell variables, `git -C`, `timeout` or `; echo $?`. Git in another directory is `cd <dir> && git …`. Long output goes to `RUN_DIR/logs/`, or is piped through `| tail`.

**Why.** The permission check cannot verify compound commands, so it asks the owner, which stalls a background agent. In Phase 6 the Haiku discovery appended `; echo "exit=$?"` to every command, and all of them were denied. macOS has no `timeout`. `git -C` always needs approval.

**Consequences.** The prompts are a little more verbose. In exchange, behaviour is reproducible, and the guards can reason about one simple command at a time.

### DD-12. Deterministic scripts for everything that is counted

**Decision.** Mechanical work is done by bash scripts (macOS bash 3.2, jq or python3), never by the model:
- **`stack-scan.sh`:** mode detection, fingerprints, staleness.
- **`run-state.sh`:** run folders, budgets, usage rows, rework caps.

**Why.** Models miscount, mis-hash and drift. A script gives the same answer every time, and its exit codes (3 = rework cap reached) are easy to act on.

**Consequences.** The prompts tell agents to call the scripts and never compute tokens, hashes or rounds themselves. The scripts are allow-listed in the settings snippet.

## Cost

### DD-13. Model tier per role

**Decision.**

| Role | Model |
|---|---|
| Orchestrator, BA, Developer, Tester | Sonnet |
| Architect: stack proposal and design | Opus, high effort |
| Architect: discovery and profile updates; Tester: full-suite pass | Haiku, through per-call `model` overrides |

`maxTurns`: BA 20, Architect 40, Developer 50, Tester 30.

**Why.** Spend goes where mistakes are most expensive: a wrong design costs more than any single call. The highest-volume roles (Developer, Tester) stay on the mid tier. Discovery and log triage are mostly reading and running commands.

**Consequences.** The Opus design step is the largest single item (163–291k per call), and Haiku discovery the second (~180k). The `maxTurns` values come from Phase 6 peaks (Developer 20, Tester 11) with headroom. `effort` has not been measured separately.

### DD-14. Measured spend, Orchestrator included, with soft and hard budgets

**Decision.** After every agent call, `run-state.sh usage` adds a row to `state.md`, summed from the subagent's transcript. Every `budget`, `usage`, `check` and `ack-soft` call also adds the Orchestrator session's requests made since the run started. The unit is **input-token equivalents**: `input + 1.25 × cache writes + 0.1 × cache reads + 5 × output`. The default budgets cover subagents plus Orchestrator:

| Size | Soft | Hard |
|---|---|---|
| S | 750k | 1.5M |
| M | 1.8M | 3.6M |
| L | 4M | 8M |

At the soft budget the Orchestrator asks whether to continue. At the hard budget it starts no further agent.

**Why.**
- The Agent tool result reports only the final request's tokens, so the transcripts are the only full record.
- Raw token totals are dominated by cheap cache reads. The weights approximate relative price.
- Phase 6 showed the Orchestrator adds 35–55% to the counted spend, and up to ~120% on small runs. Left uncounted, it would be a hidden cost.

**Rejected.**
- *Agent-reported token counts*: incomplete.
- *Dollar figures*: they depend on the plan and on pricing, and go out of date.

**History.** In Phase 6 the budgets counted subagents only (S 400k/800k, M 1.0M/2.0M, L 2.5M/5M). After Phase 6 the Orchestrator was counted too, and the defaults were raised. Projects can override them in the profile, and all projects through `DEV_TEAM_BUDGET_*`.

## Learning

### DD-15. Learning is explicit, layered and approved

**Decision.** There are three layers, all plain Markdown:
1. **The project profile.**
2. **`.team/learnings.md`:** project lessons, written by the Orchestrator at the retro. Soft cap ~150 lines; stable rules are promoted into the profile.
3. **Cross-project knowledge:** stack lessons go into `playbooks/<stack>.md`, and general lessons into the Orchestrator's user memory, which passes them on as `OWNER RULES`.

Agents only *propose* learnings in their replies. The retro is an Orchestrator step, not an extra agent call. Nothing reaches cross-project scope without the owner's approval.

**Why.** Learned rules change future behaviour, so they must be readable, editable, reviewable in git and reversible. Opaque memory would let one bad lesson spread to every project.

**Consequences.** Rules cost tokens in every later prompt. In Phase 6 one approved general rule ("re-fetch partial WebFetch pages") pushed the next stack proposal to 13 lookups, and it was narrowed at the gate. Rule growth is checked at retros. The profile records only facts that survive ordinary feature work: no test counts, no single test files.

### DD-16. Fingerprints and incremental re-discovery

**Decision.** The profile stores a fingerprint: hashes of the manifest, lock, toolchain and CI files, by category. At the start of each run `stack-scan.sh check` compares it with the project:
- **Lock-only changes:** the fingerprint is refreshed, and the refresh is mentioned at the first gate. No Gate 0.
- **Changes in a category:** an *incremental* re-discovery of just those areas, on Haiku, then Gate 0 for the changes.
- **A root manifest added or removed, a missing fingerprint, or the owner asks:** a full re-discovery.

**Why.** Profiles go stale as projects evolve, but a full re-discovery on every run would cost ~180k tokens for nothing.

**Consequences.** Gate 0 reappears only when the stack actually changed, and then shows only the old → new differences.

## Distribution

### DD-17. User-level plain files, symlinked, not a plugin

**Decision.** `scripts/install.sh` installs into `~/.claude/` (agents, skills, and `dev-team/` for templates, playbooks and hooks). By default it symlinks into this repo, and it falls back to copies. It backs up anything it would replace and writes a manifest that `uninstall.sh` uses to reverse the install exactly. `--with-settings` merges the settings snippet without overwriting existing values.

**Why.**
- *User level*: the team is available in every project. A project-level agent file with the same name can still override it.
- *Symlinks*: a `git pull` updates the team at once, and lessons written to playbooks land in this repo, where they can be committed.
- *Not a plugin*: plugin agents ignore `hooks`, `mcpServers` and `permissionMode`, which the safety design depends on (DD-9, DD-10).

**Consequences.**
- Phase 6 confirmed that symlinked agents and skills load. Permission checks resolve symlinks, so the repo's real path must be in `additionalDirectories`.
- The config dir must be `~/.claude`, because the hook commands and prompts use that path.
- Uninstall never deletes copies. It moves them aside, because copied playbooks may hold lessons.

---

## Deferred

| Idea | Why not in v0.1.0 | Revisit when |
|---|---|---|
| Agent-teams mode | DD-1: cost and control; the relayed loop was sufficient in Phase 6 | The tester ⇄ developer loop stalls on real projects |
| Plugin packaging | DD-17: plugins drop hooks and `permissionMode` | Plugin agents support them |
| Headless / CI runner (Agent SDK) | Gates assume a human; print mode works by hand | There is a need for unattended runs with pre-approved gates |
| More roles (DevOps, security reviewer, tech writer, UI/UX) | Core first | Added as new `agents/*.md` files, with no change to the core |
| Parallel agents | One agent at a time keeps state and cost simple | Independent tasks become common and wall-clock time matters |

## Other decisions

| Decision | Choice |
|---|---|
| Language | English for all prompts, docs and templates (the owner's decision) |
| What to commit in target projects | Profile, stack decision, roadmap, learnings and `.claude/agent-memory/`; `.team/runs/` is git-ignored |
| Commit style in this repo | Conventional Commits, at least one commit per phase |
| License | MIT |
