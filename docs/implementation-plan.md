# dev-team-agents — Implementation Plan

Status: **Final** · Date: 2026-11-16 · Language: English (all repo content)

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

A new component with a new stack inside an existing project (e.g. adding a mobile app to a monorepo) is a brownfield run: the Architect includes a scoped stack proposal for that component in the design, approved at Gate 2.

### Status codes (every agent ends its output with exactly one)
| Code | Meaning | Orchestrator action |
|---|---|---|
| `DONE` | Output complete | Advance to next step / gate |
| `NEEDS_HUMAN: <question + options>` | A decision only the human can make | Ask the user, resume the agent with the answer |
| `BLOCKED: <reason>` | Cannot proceed (missing info, env problem) | Route to the right role or escalate |
| `NEEDS_REWORK: <findings>` | Defects found (tester → developer, architect → ba …) | Send back; count the round |

### Gates
| Gate | Name | What the owner approves | When |
|---|---|---|---|
| 0 | **Stack** | Brownfield: the discovered project profile. Greenfield: the proposed tech stack | Once per project, and again when the profile is stale |
| 1 | **Requirements** | Scope, acceptance criteria, constraints | Every run |
| 2 | **Design** | Design, task breakdown (greenfield: also milestones) | Every run |
| 3 | **Merge** | The tested change, before it is merged | Every run (greenfield: every milestone) |

Gate 0 sits at a different point in each flow, because a stack can be *discovered* before the request is analyzed but can only be *chosen* once the requirements are known.

### Brownfield workflow
```
[first run / stale profile]  discover ─► GATE 0: confirm project profile
request ─► BA ─► GATE 1: approve requirements
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
│   ├── project-discovery/SKILL.md   # brownfield: build/refresh project-profile.md
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
│   └── settings.snippet.json        # optional: agent-teams env flag, permissions
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
    ├── state.md         # mode, current step, gate results, rework counters
    ├── requirements.md  # BA output
    ├── design.md        # Architect output
    ├── tasks.md         # Architect task breakdown, with status
    └── test-report.md   # Tester output
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
- `.team/learnings.md`: short dated entries ("what failed → what fixed it → rule going forward"), appended by agents at the end of a run.
- Agents also use `memory: project` so role-specific lessons persist per project.

### Layer 3 — Cross-project learnings
- At the end of each run a **retro** step collects candidate learnings from all roles and classifies each as *project-specific* or *general*.
- The Orchestrator proposes general ones to the human; approved items go to user-level memory (`memory: user`) or, if stack-specific but reusable, into `playbooks/<stack>.md` in this repo (committed).
- Playbooks feed back into both modes: discovery uses them to know what to look for, stack selection uses them as evidence of what has worked for this owner.
- Nothing is promoted to cross-project scope without human approval.

## 6. Phases

| # | Phase | Deliverables | Commit | Exit criteria |
|---|---|---|---|---|
| 0 | **Skeleton** | `git init`, folder structure, README stub, LICENSE, `.gitignore`, private GitHub remote, this plan under `docs/` | `chore: init repo skeleton and implementation plan` | Repo pushed to private remote; tree matches §4 |
| 1 | **Hand-off contract** | `team-handoff` skill; per-run `.team/` templates including `state.md`; status codes and rework protocol | `feat: hand-off contract and templates` | Each role's inputs/outputs defined on one page |
| 2 | **Stack knowledge + learning** | `project-discovery` and `stack-selection` skills; `project-profile`, `stack-decision`, `roadmap`, `learnings` templates; mode-detection rule; fingerprint/staleness rule; retro protocol | `feat: stack discovery, stack selection and learning` | Discovery on 2 different-stack repos yields correct commands; stack selection on an empty directory yields 2–3 justified options with current versions |
| 3 | **Role agents** | `ba`, `architect`, `developer`, `tester` with `tools`, `model`, `skills`, `memory`, `permissionMode`, `maxTurns`. BA and Architect never edit source: they write only under `.team/`. Architect additionally has web access for version checks. Developer uses `isolation: worktree`. Tester runs tests and may add test files, but cannot edit production source | `feat: add ba, architect, developer, tester agents` | Each agent, invoked alone, produces its output in the expected format and cannot write outside its allowed paths |
| 4 | **Orchestrator + gates** | `orchestrator.md`; mode detection; brownfield and greenfield flows; Gates 0–3; `NEEDS_HUMAN` routing via `AskUserQuestion`; rework-round cap; `state.md` updates and resume; tools: `Agent(ba, architect, developer, tester)` plus file tools, `Bash` and `AskUserQuestion` | `feat: orchestrator with modes and approval gates` | Correct mode chosen for an empty dir, an existing repo and an ambiguous dir (asks); on an ambiguous request the orchestrator stops and asks; rework cap triggers escalation; an interrupted run resumes from `state.md` |
| 5 | **Safety + install** | `guard-bash.sh` and `guard-write.sh` hooks; `install.sh` / `uninstall.sh` (symlink with copy fallback, backups); `settings.snippet.json` | `feat: install script and guard hooks` | One-command install on a clean machine; destructive commands are blocked or require approval; out-of-scope writes are blocked |
| 6 | **End-to-end validation** | Three dry-runs: one **greenfield** ("build a small REST API with login from scratch") and two **brownfield** on small projects with different stacks ("add authentication"); notes in `docs/`; prompt fixes | `test: e2e dry-run notes and prompt fixes` | All scenarios complete with only gate approvals; the greenfield run ends with a verified profile and a passing skeleton; a follow-up request on that project runs as Established; learnings written correctly; token cost acceptable |
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
| Rework loop | Orchestrator-relayed, max 3 rounds | Subagents report only to their caller; keeps cost predictable |

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
| Token cost | Cheaper models for BA/Architect, `maxTurns` per agent, subagents before agent teams, one milestone per run |
| First prompts are imperfect | Plan 1–2 prompt-tuning iterations after Phase 6 |

## 9. To verify during implementation
- Whether symlinks inside `~/.claude/agents/` are picked up reliably (else copy).
- Exact `memory: project` / `memory: user` behavior and file locations.
- `claude --agent orchestrator` behavior with a restricted `Agent(...)` tool list.
- Hook behavior for subagent-defined `PreToolUse` hooks in practice, including path-based write restriction for BA/Architect/Tester.
- Whether the `skills:` preload keeps agent prompts small enough.
- `isolation: worktree` in a repo that was just initialized (empty repo, single initial commit).
- How the Tester reaches the Developer's worktree, and how a rework round continues in the same worktree (resume the same Developer agent vs. an Orchestrator-managed branch).
- Whether the Architect's web access gives reliable current-version information for stack proposals.

## 10. Out of scope (v0.1.0)
Agent-teams mode, plugin packaging, CI/headless runner, additional roles (DevOps, security reviewer, tech writer, UI/UX designer), automated deployment of greenfield projects. These can be added as new `agents/*.md` files without changing the core.
