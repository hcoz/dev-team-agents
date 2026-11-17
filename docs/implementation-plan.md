# dev-team-agents — Implementation Plan

Status: **Final** · Date: 2026-11-16 (rev. 2026-11-17: cost controls) · Language: English (all repo content)

## 1. Goal

A reusable, version-controlled **multi-agent software team** for Claude Code: Business Analyst (BA), Architect, Developer, Tester, coordinated by an Orchestrator. The owner gives a rough request; the team analyzes, designs, implements and tests it, pausing for human approval at defined gates and resolving internal problems among themselves.

The team works in two modes:

| Mode | Starting point | Example request | How the stack is established |
|---|---|---|---|
| **Greenfield** | Empty or near-empty directory | "Build a booking app for a small clinic" | The team **proposes** a tech stack from the requirements; the owner approves it |
| **Brownfield** | Existing codebase | "Add auth to the project" | The team **discovers** the existing stack and conventions; the owner confirms them |

The team must:
- work in **any project, any stack** and **learn** each project's conventions over time;
- be installed **once** at user level (`~/.claude/`) and be available in every project;
- live in a **private GitHub repo**, local path `/Users/hco/Projects/dev-team-agents`, with a clean commit history.

## 2. Design principles

1. **Stack-agnostic core.** No agent prompt hardcodes a language, framework or test command. Stack knowledge is *decided* (greenfield) or *discovered* (brownfield) per project and stored on disk.
2. **One source of truth for the stack.** Both modes produce the same artifact, `.team/project-profile.md`. Once it exists and is verified, every later run is handled identically, whatever the project's origin.
3. **State lives on disk, not in conversation.** Subagents have isolated context, so all hand-offs go through files in the target project's `.team/` directory. The Orchestrator's own progress is on disk too, so an interrupted run can resume.
4. **Humans decide at gates; agents decide everything else.** Subagents cannot ask the user questions directly (`AskUserQuestion` is removed from subagent tool pools), so all human interaction is routed through the Orchestrator.
5. **Subagents first, agent teams later.** Start with the cheaper, more controllable subagent + orchestrator model. Move to experimental agent teams (peer-to-peer messaging) only if the tester↔developer loop proves insufficient.
6. **Least privilege per role.** Each agent gets only the tools and write paths its job needs.
7. **Learning is explicit and reviewable.** Learned knowledge is written to plain Markdown files a human can read, edit and commit.

## 3. Architecture

```
You ──► Orchestrator (main session: `claude --agent orchestrator`)
           │  detects mode, reads/writes .team/ state, owns all human interaction
           ├─► architect (discover)       → project-profile.md          [brownfield]
           ├─► ba                         → requirements.md
           ├─► architect (stack proposal) → stack-decision.md           [greenfield]
           ├─► architect (design)         → design.md, tasks.md, roadmap.md
           ├─► developer                  → code (isolated git worktree)
           └─► tester                     → test-report.md
```

### Mode detection (first step of every run)
| Condition in the working directory | Mode |
|---|---|
| `.team/project-profile.md` exists with status `verified` | **Established** — skip to the request; re-run discovery only if the fingerprint is stale |
| Source code or a build manifest exists, no profile | **Brownfield** — run discovery |
| Empty, or only README / LICENSE / `.gitignore` / notes | **Greenfield** — run stack selection |
| Anything ambiguous (a few stray files, an abandoned prototype) | Orchestrator **asks the owner** |

The owner can always force a mode in the request ("treat this as greenfield"). The detected mode is recorded in the run's `state.md` and shown at the first gate.

After mode detection the Orchestrator **sizes the request** (S / M / L, see *Cost controls* below), which decides how much of the workflow runs.

A new component with a new stack inside an existing project (e.g. adding a mobile app to a monorepo) is a brownfield run: the Architect includes a scoped stack proposal for that component in the design, approved at Gate 2.

### Status codes (every agent ends its output with exactly one)
| Code | Meaning | Orchestrator action |
|---|---|---|
| `DONE` | Output complete | Advance to next step / gate |
| `NEEDS_HUMAN: <question + options>` | A decision only the human can make | Ask the user, resume the agent with the answer |
| `BLOCKED: <reason>` | Cannot proceed (missing info, env problem) | Route to the right role or escalate |
| `NEEDS_REWORK: <findings>` | Defects found (tester → developer, architect → ba …) | Send back; count the round |

**Return contract:** an agent's final message to the Orchestrator has three parts: a summary of at most ~10 lines, the paths of the files it wrote or changed, and the status code. Full content goes in `.team/` files, never in the reply. This keeps the Orchestrator's context small (see *Cost controls*).

### Gates
| Gate | Name | What the owner approves | When |
|---|---|---|---|
| 0 | **Stack** | Brownfield: the discovered project profile. Greenfield: the proposed tech stack | Once per project, and again when the profile is stale |
| 1 | **Requirements** | Scope, acceptance criteria, constraints | Every L run; S and M runs merge Gates 1 and 2 into one gate |
| 2 | **Design** | Design, task breakdown (greenfield: also milestones) | Every L run; S and M runs merge Gates 1 and 2 into one gate |
| 3 | **Merge** | The tested change, before it is merged | Every run (greenfield: every milestone) |

Gate 0 sits at a different point in each flow, because a stack can be *discovered* before the request is analyzed but can only be *chosen* once the requirements are known.

### Brownfield workflow
```
[first run / stale profile]  discover ─► GATE 0: confirm project profile
request ─► size S / M / L  (L shown below; S and M are shorter, see Cost controls)
        ─► BA ─► GATE 1: approve requirements
        ─► Architect ─► GATE 2: approve design + task breakdown
        ─► Developer ⇄ Tester  (max 3 rework rounds per task, then escalate)
        ─► GATE 3: approve before merge
        ─► Retro: collect learnings (see §5)
```

### Greenfield workflow
```
request ─► BA: product brief (users, scope, MVP, constraints) ─► GATE 1: approve requirements
        ─► Architect: stack proposal, 2–3 options + recommendation ─► GATE 0: approve stack
        ─► Architect: design + roadmap + tasks for milestone M0 ─► GATE 2: approve design
        ─► Bootstrap M0 (walking skeleton):
             Orchestrator: git init + initial commit if needed (covered by Gate 0 approval)
             Developer: scaffold project, tooling, CI, one thin end-to-end slice
             Tester: run every command in the profile; profile becomes `verified`
        ─► GATE 3: approve before merge
        ─► Retro
later milestones (M1, M2 …) ─► normal runs in Established mode, one milestone per run
```

Greenfield specifics:
- **BA collects stack constraints** along with the requirements: languages the owner knows, hosting and budget, deadlines, compliance, must-use or must-avoid technologies. Missing answers are raised as `NEEDS_HUMAN`.
- **The Architect never picks silently.** `stack-decision.md` lists 2–3 candidate stacks with trade-offs against the approved requirements, one recommendation, and for the recommended stack: language/runtime, framework, database, package manager, test tooling, lint/format, CI, deployment target, repo layout. Versions are checked against current official docs, not recalled from memory. Matching `playbooks/<stack>.md` files are consulted.
- **At Gate 0 the owner can** approve the recommendation, pick another option, or change individual choices. The result is recorded as a decision record and kept in the repo.
- **Scope is sliced into milestones** in `roadmap.md`. M0 is always the walking skeleton; a run never tries to build the whole product in one Developer ⇄ Tester loop.
- **After M0 the project is no longer special.** The profile is verified, and every further run follows the brownfield workflow without Gate 0.

### Inter-agent communication
- **Default:** agents report to the Orchestrator, which relays (e.g. tester finds a bug → `NEEDS_REWORK` → Orchestrator re-invokes developer with the report). Rework rounds are capped at 3 per task.
- **Optional (Phase 8):** agent teams, where teammates message each other directly via a shared task list. Experimental, disabled by default, higher token cost.

### Cost controls
Cost is controlled at four levels: how much of the workflow runs, how much each call may spend, how much context each agent loads, and how fast the shared files grow.

**1. Right-size the workflow (biggest lever).** The Orchestrator proposes a size from the request and a quick look at the profile; the owner confirms or overrides it at the first gate.

| Size | Typical request | Flow | Gates |
|---|---|---|---|
| **S** | Bug fix, small change in 1–3 files; no new API, schema or dependency | Orchestrator writes a short scope note in `state.md` ─► Developer ⇄ Tester | Scope (merged Gates 1+2), Gate 3 |
| **M** | One feature in a known area, a few tasks | Architect writes requirements and design in one step (no separate BA call) ─► Developer ⇄ Tester | Merged Gates 1+2, Gate 3 |
| **L** | Cross-cutting feature, new component, unclear scope | Full workflow | Gates 1, 2, 3 |

- Greenfield runs up to and including M0 are always **L**.
- Any agent that finds the work is bigger than its size returns `NEEDS_HUMAN: upsize to M/L?`. The Orchestrator never upsizes on its own.
- An S run skips the retro unless an agent reported a candidate learning.

**2. Budgets and measurement.**
- After every agent call the Orchestrator appends a row to `state.md`: agent, step, model, tokens, duration, rework round. The Agent tool result reports these figures.
- Each run has a **soft** and a **hard** token budget per size. Defaults live in `settings/settings.snippet.json`; `project-profile.md` can override them. At the soft budget the Orchestrator shows the spend so far and asks before continuing. At the hard budget it stops and escalates.
- Rework caps: max 3 rounds per task **and** max 8 rounds per run, then escalate.
- Default budgets are set from the Phase 6 baselines and refined at each retro.

**3. Model and effort per role.** Set `model` and `effort` in each agent's frontmatter. The Orchestrator may override `model` per call.

| Role / step | Model tier | Reason |
|---|---|---|
| Orchestrator | Mid (e.g. Sonnet) | Mostly routing and file updates; long-lived context |
| BA | Mid | Structured writing |
| Architect: discovery | Cheap (e.g. Haiku), via per-call override | Reads manifests and CI files, runs commands |
| Architect: stack proposal, design | Strongest (e.g. Opus), high effort | Highest-leverage decisions; design mistakes are the costliest to fix later |
| Developer | Mid | Highest token volume |
| Tester | Mid; cheap for log triage | Mostly running commands and reading output |

Starting `maxTurns` values, tuned in Phase 6: BA 20, Architect 40, Developer 80, Tester 40.

**4. Keep context small.**
- **Orchestrator:** agents follow the return contract. The Orchestrator re-reads `.team/` files only when a step needs them. Since all state is on disk, a long run (e.g. a greenfield milestone) can continue in a fresh Orchestrator session that resumes from `state.md`.
- **Targeted reading:** `tasks.md` lists, per task, the files to touch, the entry points and the relevant tests. The Developer starts from that list instead of exploring the repo. The Tester gets the diff and the affected test paths.
- **Test output:** the Tester runs targeted tests during rework and the full suite only once, before Gate 3. Raw logs go to `.team/runs/<run-id>/logs/`. Only failures and a summary are returned.
- **Rework:** the Developer is resumed in the same worktree with its context intact, not restarted cold. This is confirmed during implementation (§9).
- **Stable prompts:** agent prompts and preloaded skills stay short and change rarely, so prompt caching works. Long reference material goes in skills that agents load on demand, not in `skills:` preload.
- **Web lookups:** the Architect is limited to ~10 web lookups per stack proposal and checks official docs and release pages first.

**5. Cap the files that grow.**
- `learnings.md` has a soft cap of ~150 lines. The retro compacts it: merge duplicates, drop entries that no longer apply, and promote stable rules into the profile's conventions section.
- Staleness re-discovery is **incremental**: only the areas whose manifest, lock or CI files changed are re-checked. A full re-discovery happens only when the owner asks or the layout changed.
- The retro is not a separate agent call. Each agent lists candidate learnings in its final output, and the Orchestrator collects and classifies them.

## 4. Repository structure

```
dev-team-agents/
├── README.md
├── LICENSE
├── .gitignore
├── agents/
│   ├── orchestrator.md
│   ├── ba.md
│   ├── architect.md
│   ├── developer.md
│   └── tester.md
├── skills/
│   ├── team-handoff/SKILL.md        # status codes, file formats, rework protocol
│   ├── project-discovery/SKILL.md   # mode detection; brownfield: build/refresh project-profile.md
│   │   └── scripts/stack-scan.sh    # mode, fingerprint, staleness check (deterministic)
│   ├── stack-selection/SKILL.md     # greenfield: propose a stack, write stack-decision.md
│   └── definition-of-done/SKILL.md  # generic DoD, extended by the project profile
├── playbooks/                       # optional, grows over time (e.g. python-flask.md)
├── hooks/
│   ├── guard-bash.sh                # blocks/asks on destructive or outward-facing commands
│   └── guard-write.sh               # limits each role's writes to its allowed paths
├── templates/team/                  # skeletons for .team/ files in target projects
│   ├── project-profile.md
│   ├── stack-decision.md
│   ├── roadmap.md
│   ├── learnings.md
│   ├── state.md
│   ├── requirements.md
│   ├── design.md
│   ├── tasks.md
│   └── test-report.md
├── settings/
│   └── settings.snippet.json        # optional: agent-teams env flag, permissions, default cost budgets
├── scripts/
│   ├── install.sh                   # idempotent; backs up existing files
│   └── uninstall.sh
└── docs/
    ├── implementation-plan.md       # this file
    └── design-decisions.md
```

### Per-project state (created in the *target* project, not in this repo)
```
<project>/.team/
├── project-profile.md   # stack, commands, conventions; origin: decided | discovered
├── stack-decision.md    # greenfield only: options considered, choice, reasons
├── roadmap.md           # greenfield only: milestones and their status
├── learnings.md         # append-only, dated lessons for this project
└── runs/<run-id>/       # one folder per request, e.g. 2026-11-16-add-auth
    ├── state.md         # mode, size, current step, gate results, rework counters, usage log
    ├── requirements.md  # BA output (M runs: written by the Architect)
    ├── design.md        # Architect output
    ├── tasks.md         # Architect task breakdown, with status and files to touch
    ├── test-report.md   # Tester output
    └── logs/            # raw test and command output, never returned inline
```
Recommendation: commit `project-profile.md`, `stack-decision.md`, `roadmap.md` and `learnings.md` so knowledge persists and is shared; git-ignore `.team/runs/`.

## 5. Stack knowledge and learning

### Layer 1 — Project profile
`project-profile.md` is the single description of the stack that every agent reads before acting. Agents must use the commands recorded there instead of guessing. Contents:
- languages, frameworks, package manager(s), monorepo layout;
- exact commands: install, build, lint, type-check, unit/integration tests, run locally;
- test layout and conventions, directory structure, naming and commit/branch conventions;
- CI configuration, environments, risky areas (migrations, secrets, generated code);
- `origin` (`decided` or `discovered`) and `status` (`planned` or `verified`);
- a **fingerprint** (hash of manifest/lock/CI files) so the Orchestrator can detect staleness and re-run discovery.

How it is produced:
- **Brownfield — discovered.** The Architect follows the `project-discovery` skill without touching source code, then runs the recorded commands where safe to confirm they work. The owner confirms the profile at Gate 0.
- **Greenfield — decided.** After Gate 0 the Architect derives the profile from `stack-decision.md` with status `planned`. The Developer scaffolds to match it; the Tester runs every command; only then does the status become `verified` and the fingerprint get computed. Any deviation found while scaffolding is corrected in the profile and reported at Gate 3.

### Layer 2 — Project learnings
- `.team/learnings.md`: short dated entries ("what failed → what fixed it → rule going forward"), appended by agents at the end of a run. Soft cap of ~150 lines; the retro compacts it (see *Cost controls*).
- Agents also use `memory: project` so role-specific lessons persist per project.

### Layer 3 — Cross-project learnings
- At the end of each run a **retro** step (done by the Orchestrator, not a separate agent call) collects the candidate learnings each role listed in its final output and classifies each as *project-specific* or *general*.
- The Orchestrator proposes general ones to the human; approved items go to user-level memory (`memory: user`) or, if stack-specific but reusable, into `playbooks/<stack>.md` in this repo (committed).
- Playbooks feed back into both modes: discovery uses them to know what to look for, stack selection uses them as evidence of what has worked for this owner.
- Nothing is promoted to cross-project scope without human approval.

## 6. Phases

| # | Phase | Deliverables | Commit | Exit criteria |
|---|---|---|---|---|
| 0 | **Skeleton** | `git init`, folder structure, README stub, LICENSE, `.gitignore`, private GitHub remote, this plan under `docs/` | `chore: init repo skeleton and implementation plan` | Repo pushed to private remote; tree matches §4 |
| 1 | **Hand-off contract** | `team-handoff` skill; per-run `.team/` templates including `state.md` with a usage log table; status codes, return contract and rework protocol; `tasks.md` with files to touch per task | `feat: hand-off contract and templates` | Each role's inputs/outputs defined on one page |
| 2 | **Stack knowledge + learning** | `project-discovery` and `stack-selection` skills; `project-profile`, `stack-decision`, `roadmap`, `learnings` templates; mode-detection rule; fingerprint/staleness rule with incremental re-discovery; retro protocol with `learnings.md` compaction | `feat: stack discovery, stack selection and learning` | Discovery on 2 different-stack repos yields correct commands; stack selection on an empty directory yields 2–3 justified options with current versions |
| 3 | **Role agents** | `ba`, `architect`, `developer`, `tester` with `tools`, `model`, `effort`, `skills`, `memory`, `permissionMode`, `maxTurns`, using the model tiers and starting `maxTurns` from *Cost controls*. BA and Architect never edit source: they write only under `.team/`. Architect additionally has web access for version checks. Developer uses `isolation: worktree`. Tester runs tests and may add test files, but cannot edit production source. Also `definition-of-done` skill and `guard-write.sh` (moved here from Phase 5, because the exit criterion needs write scopes enforced) | `feat: add ba, architect, developer, tester agents` | Each agent, invoked alone, produces its output in the expected format and cannot write outside its allowed paths |
| 4 | **Orchestrator + gates** | `orchestrator.md`; mode detection; request sizing (S/M/L) and the matching flows; brownfield and greenfield flows; Gates 0–3; `NEEDS_HUMAN` routing via `AskUserQuestion`; per-task and per-run rework caps; soft/hard budgets; usage logging; `state.md` updates and resume; tools: `Agent(ba, architect, developer, tester)` plus file tools, `Bash` and `AskUserQuestion` | `feat: orchestrator with modes and approval gates` | Correct mode chosen for an empty dir, an existing repo and an ambiguous dir (asks); a one-line fix is sized S and skips BA/Architect; on an ambiguous request the orchestrator stops and asks; rework caps and the hard budget trigger escalation; the soft budget triggers a question; an interrupted run resumes from `state.md` |
| 5 | **Safety + install** | `guard-bash.sh` hook (`guard-write.sh` exists since Phase 3); `install.sh` / `uninstall.sh` (symlink with copy fallback, backups); `settings.snippet.json` including default budgets | `feat: install script and guard hooks` | One-command install on a clean machine; destructive commands are blocked or require approval; out-of-scope writes are blocked |
| 6 | **End-to-end validation** | Three dry-runs: one **greenfield** ("build a small REST API with login from scratch") and two **brownfield** on small projects with different stacks ("add authentication"), plus one **S-size** request per brownfield project; notes in `docs/` including a per-agent cost table for each scenario, taken from `state.md`; prompt fixes; default budgets and `maxTurns` set from these baselines | `test: e2e dry-run notes and prompt fixes` | All scenarios complete with only gate approvals; the greenfield run ends with a verified profile and a passing skeleton; a follow-up request on that project runs as Established; learnings written correctly; every run stays within its hard budget; an S run costs well under an L run (target ≤ 25%); after prompt fixes, re-running one L scenario is no more expensive than its first run |
| 7 | **Release** | Final README (install, usage for both modes, flow diagrams), `docs/design-decisions.md`, tag `v0.1.0`, push | `docs: usage guide` + tag `v0.1.0` | A new user can install and start either mode from the README alone |
| 8 | **Optional** | Agent-teams mode; plugin packaging; Agent SDK headless/CI runner | separate branches | Only if Phase 6 shows the orchestrator-relayed loop is insufficient |

Commit conventions: Conventional Commits, one commit per phase minimum, small focused commits within a phase, work on short-lived branches merged to `main`.

## 7. Key decisions

| Decision | Choice | Reason |
|---|---|---|
| Operating modes | Greenfield and brownfield, auto-detected, owner can override | The team must both start projects and join existing ones |
| Stack handling | Always recorded in `.team/project-profile.md`: decided in greenfield, discovered in brownfield | One artifact for all agents; both modes converge after the first run |
| Greenfield stack choice | Architect proposes 2–3 options with a recommendation; owner approves at Gate 0, after requirements | A stack can only be judged against known requirements; the owner keeps the final say |
| Greenfield scope | Milestones in `roadmap.md`; M0 is a walking skeleton; one milestone per run | Keeps each run reviewable and the rework loop bounded |
| Language | English for all prompts, docs, templates, README | Owner's decision |
| Repo | Private GitHub repo at `/Users/hco/Projects/dev-team-agents` | Owner's decision |
| Scope of agents | User level (`~/.claude/agents/`) | Available in every project; project-level files can override |
| Human gates | Gates 1–3 every run; Gate 0 once per project or on a stale profile | The stack is verified once, not on every request |
| Run state | One folder per request under `.team/runs/`, with `state.md` | Runs do not overwrite each other and can resume after interruption |
| BA/Architect permissions | No source edits; writes limited to `.team/` by hook | They must write their own hand-off files, which a fully read-only mode would prevent |
| Install method | Symlink, copy fallback | Repo updates propagate instantly; verify symlinks are scanned in Phase 5 |
| Distribution | Plain user-level files, not a plugin (for now) | Plugin agents ignore `hooks`, `mcpServers`, `permissionMode`, which the safety design needs |
| Rework loop | Orchestrator-relayed, max 3 rounds per task and 8 per run | Subagents report only to their caller; keeps cost predictable |
| Request sizing | S / M / L proposed by the Orchestrator, confirmed by the owner; S and M skip or merge steps and gates | Small changes should not pay for the full pipeline |
| Cost budgets | Usage logged per agent call in `state.md`; soft budget asks, hard budget stops | Cost becomes visible and bounded, not just "acceptable" |
| Model tiering | Strongest model only for the Architect's design and stack decisions; mid tier for most roles; cheap tier for discovery and log triage | Spend goes where mistakes are most expensive; the highest-volume roles stay on the mid tier |
| Agent replies | Short summary + file paths + status code; content lives in `.team/` | Keeps the long-lived Orchestrator context small |

## 8. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Endless tester↔developer loop | 3-round cap in the orchestrator prompt, then escalate to the human |
| Wrong stack assumptions (brownfield) | Gate 0 confirmation; agents must use commands from the profile; stale-profile detection by fingerprint |
| Poor stack choice (greenfield): over-engineered, unfamiliar to the owner, or outdated | BA collects owner constraints first; every option is justified against the requirements; one option is always the simplest stack that meets them; versions checked against current docs; owner decides at Gate 0 |
| Greenfield scope explosion | MVP defined at Gate 1; milestones in `roadmap.md`; M0 limited to a walking skeleton |
| Wrong mode detected | Explicit rules in §3; ask when ambiguous; mode shown at the first gate; owner override |
| Planned profile does not match the scaffold | Profile stays `planned` until the Tester has run every command; deviations reported at Gate 3 |
| Target directory is not a git repo, or has no commits | Orchestrator asks to initialize git and make an initial commit before the Developer starts, since worktree isolation needs one |
| Bad learnings polluting future runs | Learnings are plain files, reviewable and committed; cross-project promotion requires human approval |
| Developer changes land unreviewed | Worktree isolation; Gate 3 before any merge; no auto-merge or auto-push |
| Destructive shell commands or out-of-scope writes | `guard-bash.sh` and `guard-write.sh` PreToolUse hooks; least-privilege `tools` lists |
| Token cost | See §3 *Cost controls*: S/M/L request sizing, soft/hard budgets with usage logging, per-role model and effort tiers, `maxTurns` per agent, summary-only replies, targeted reading and testing, subagents before agent teams, one milestone per run |
| Cost creeping up over time (`learnings.md` growth, longer prompts, full re-discovery) | `learnings.md` cap and compaction; incremental re-discovery; prompts and preloads kept short; Phase 6 baselines compared at later retros |
| Undersized request (S run turns out to be L) | Agents return `NEEDS_HUMAN: upsize`; the hard budget stops runaway runs |
| First prompts are imperfect | Plan 1–2 prompt-tuning iterations after Phase 6 |

## 9. To verify during implementation
- Whether symlinks inside `~/.claude/agents/` are picked up reliably (else copy).
- Install must also provide `~/.claude/dev-team/` (templates and playbooks, referenced by the skills) and keep `skills/project-discovery/scripts/stack-scan.sh` executable.
- Exact `memory: project` / `memory: user` behavior and file locations.
- `claude --agent orchestrator` behavior with a restricted `Agent(...)` tool list.
- Hook behavior for subagent-defined `PreToolUse` hooks in practice, including path-based write restriction for BA/Architect/Tester.
- Whether the `skills:` preload keeps agent prompts small enough.
- `isolation: worktree` in a repo that was just initialized (empty repo, single initial commit).
- How the Tester reaches the Developer's worktree, and how a rework round continues in the same worktree (resume the same Developer agent vs. an Orchestrator-managed branch).
- Whether the Architect's web access gives reliable current-version information for stack proposals.
- Whether subagent `effort` frontmatter and per-call `model` overrides behave as expected (e.g. a cheap model for Architect discovery).
- Whether the token and duration figures in Agent tool results are reliable enough for budget checks, and how to sum them per run.
- Cost of resuming the Developer for rework vs. starting it cold, measured in Phase 6.
- Install must provide `~/.claude/dev-team/hooks/guard-write.sh` (executable): agent frontmatter calls it with `onFailure: block`, so a missing script blocks every write. Requires Claude Code v2.1.295+.
- `isolation: worktree` branches from the default branch, not `HEAD`. Multi-task runs: resume one Developer for the whole run, or start a fresh one per task with `START_FROM` (fast-forward). Pick one in Phase 4 and measure the cost in Phase 6.
- Where `memory: project` writes for the worktree-isolated Developer (main checkout or worktree), and that the Developer can append logs to `RUN_DIR/logs/` from inside its worktree.
- `guard-write.sh` relies on `CLAUDE_PROJECT_DIR` being the main checkout inside subagents; confirm it in a live run. Writes through Bash redirection are not covered by it (that is `guard-bash.sh`).
- The Tester's test-file rule is a filename/directory heuristic; check it against the Phase 6 stacks.
- Architect and Tester use `permissionMode: default`, so project commands prompt unless settings allow them; Phase 5's settings snippet should cover the common read/test commands. A parent session in `acceptEdits`, auto or bypass mode overrides every agent's `permissionMode`.

## 10. Out of scope (v0.1.0)
Agent-teams mode, plugin packaging, CI/headless runner, additional roles (DevOps, security reviewer, tech writer, UI/UX designer), automated deployment of greenfield projects. These can be added as new `agents/*.md` files without changing the core.
