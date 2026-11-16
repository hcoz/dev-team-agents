---
name: team-handoff
description: Hand-off contract for the dev team (orchestrator, ba, architect, developer, tester). Defines the .team/ run folder, which role reads and writes which file, the status codes, the reply format and the rework protocol. Use whenever you act as one of these roles or read or write files under .team/.
---

# Team hand-off contract

Every role follows this contract. State lives in files, not in conversation: if something is not in a `.team/` file or in your final reply, the next role does not know it.

## 1. Where state lives

```
<project>/.team/
├── project-profile.md   stack-decision.md   roadmap.md   learnings.md   # project level
└── runs/<run-id>/
    ├── state.md   requirements.md   design.md   tasks.md   test-report.md
    └── logs/
```

- `<run-id>` is `YYYY-MM-DD-<short-slug>`, e.g. `2026-11-16-add-auth`. If the folder exists, add `-2`, `-3` …
- `~/.claude/dev-team/` is the dev-team-agents install. It holds `templates/team/` and `playbooks/`.
- The Orchestrator creates the run folder and every run file from the templates. Other roles fill in the sections already there. They do not add, rename or remove sections. A section that does not apply gets `n/a`.
- Every call from the Orchestrator gives two absolute paths: `PROJECT` (the main checkout) and `RUN_DIR`. Always read and write `.team/` through these paths. The Developer's worktree has no `.team/runs/` (it is git-ignored), so never use a relative `.team/` path inside a worktree.

## 2. Roles: inputs and outputs

| Role · step | Runs in | Reads | Writes (owns) | Reply must also state |
|---|---|---|---|---|
| **Orchestrator** | every run | request, `.team/` files as a step needs them, Agent results | `state.md` and `learnings.md` (sole writer); `Status` columns of `tasks.md` and `roadmap.md`; in `project-profile.md` only `Status`, the fingerprint block and *Promoted rules*; run folder; `git init` and merge after approval | (talks to the human) |
| **BA** | L | request (in prompt), profile, learnings | `requirements.md` | open questions, as `NEEDS_HUMAN` |
| **Architect · discover** | brownfield, missing or stale profile | repo (read only), playbooks | `project-profile.md` | profile commands that failed |
| **Architect · stack proposal** | greenfield | `requirements.md`, playbooks, official docs | `stack-decision.md` | recommended option |
| **Architect · design** | M, L | L: `requirements.md`; M: request; profile, learnings | `design.md`, `tasks.md`; greenfield: `roadmap.md`; M: also `requirements.md` | requirement issues, if any |
| **Developer** | S, M, L | its task in `tasks.md` (S: scope note in `state.md`), `design.md`, profile, learnings; on rework: `test-report.md` | code and commits in its worktree | worktree path, branch, head commit; per finding ID: fixed or disputed |
| **Tester** | S, M, L | `tasks.md` (relevant tests), acceptance criteria in `requirements.md` (S: scope note), profile commands, `git diff <base>..<head>` | `test-report.md`, `logs/`, test files in the worktree | verdict, open finding IDs |

Rules for every role:
- **Write only the files you own.** If someone else's file needs a change, say so in your reply. The Orchestrator routes it.
- **Use the commands in `project-profile.md`.** Never guess build or test commands. If a command is missing or broken, return `BLOCKED`.
- **Read narrowly.** Start from what `tasks.md` lists (files to touch, entry points, tests). Go beyond that only when you need to, and say why in your reply.
- **Logs go to files.** Write long command output to `RUN_DIR/logs/<role>-<task-or-step>-r<round>.log`, e.g. `tester-T2-r1.log`. Never paste it into a reply.

## 3. Code hand-off

- The Developer works in an isolated git worktree. It commits on its own branch there, and never pushes or merges.
- After each Developer call the Orchestrator records the worktree path, branch, base commit (the commit the branch started from) and head commit in `state.md`.
- The Tester works in the same worktree and reviews `git diff <base>..<head>`. It may add or fix test files and commits them separately as `test: …`. It never edits production source. A defect in production code becomes a finding.
- Only the Orchestrator merges, and only after Gate 3 approval.

## 4. Status codes

The last line of your reply is exactly one of these:

| Line | Use when | Orchestrator then |
|---|---|---|
| `DONE` | Your output is complete | Moves to the next step or gate |
| `NEEDS_HUMAN: <question> Options: (a) … (b) …` | Only the owner can decide (scope, trade-off, size) | Asks the owner, resumes you with the answer |
| `BLOCKED: <reason>` | You cannot proceed (missing input, broken environment, missing command) | Routes to the right role or to the owner |
| `NEEDS_REWORK: <role> — <finding IDs>` | Another role's output has defects (e.g. `NEEDS_REWORK: developer — F1, F3`) | Sends the findings back and counts a round |

- One status line, nothing after it.
- **Size:** if the work is bigger than the run's size, stop and return `NEEDS_HUMAN: upsize to M|L? <reason> Options: (a) upsize (b) cut scope to fit`. Never upsize on your own.
- **Decide where you can.** Ask only what changes the outcome and cannot be answered from the repo, the profile or the requirements. List your recommended option first.

## 5. Reply format (return contract)

Keep the final reply short. Content goes in files.

```
## Summary
<at most ~10 lines: what you did, key decisions, what the next role must know>

## Files
- <absolute path> — created | updated

## Learnings
- <what failed → what fixed it → rule going forward>   (or: none)

<status line>
```

Do not paste file contents, diffs or logs into the reply.

## 6. Rework protocol

1. The reviewing role writes each finding to its own output file with an ID: Tester `F1, F2 …` in `test-report.md`, Architect `RQ1, RQ2 …` in the *Requirement issues* section of `design.md`. IDs stay the same across rounds. The reviewer then returns `NEEDS_REWORK`.
2. The Orchestrator increments the counters in `state.md` and checks the caps: **3 rounds per task, 8 per run**.
3. **Under the cap:** the Orchestrator resumes the same agent with `RUN_DIR`, the findings file and the IDs. The Developer continues in the same worktree with its context intact.
4. The fixing role handles every listed ID. Its summary marks each one *fixed*, or *disputed* with a reason.
5. The reviewer re-checks only the listed findings and the affected tests. The Tester runs the full suite once, before Gate 3.
6. **Disputed findings:** the Orchestrator decides when the requirements settle the question. Otherwise it asks the owner.
7. **At the cap:** the Orchestrator stops and asks the owner to choose: (a) allow more rounds, (b) cut or change the scope, (c) abort the run.

## 7. Run state and usage

- Only the Orchestrator writes `state.md`. After every agent call it adds a usage-log row (agent, step, model, tokens, duration, rework round, status) using the figures from the Agent tool result.
- Before each call it compares the tokens spent with the run's soft and hard budgets.
- When a run resumes, `state.md` is the source of truth for the current step, gate results, counters and worktree.

## 8. Learnings

- Every role reads `.team/learnings.md` and the profile's *Promoted rules* before acting.
- Report candidate learnings only in your reply's *Learnings* section. Never write `learnings.md` yourself.
- The Orchestrator classifies them and writes them down at the retro: see [retro.md](retro.md).
