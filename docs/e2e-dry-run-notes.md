# End-to-end dry-run notes (Phase 6)

Date: 2026-11-17 · Claude Code 2.1.325 · macOS (bash 3.2, no GNU coreutils) · team installed with `scripts/install.sh` (symlink mode)

## 1. How the runs were driven

- Each scenario ran as `claude -p --agent orchestrator` in a disposable fixture project, one Orchestrator turn per call, continued with `--resume <session>`. The gate answers came from a stand-in owner (the Claude session running Phase 6), not from a human.
- In print mode `AskUserQuestion` is not available. The Orchestrator falls back to a written brief with numbered questions and ends its turn. This is now ground rule 8 in `agents/orchestrator.md`.
- Permissions came from a `--settings` file per fixture. It held the settings snippet (budgets, the team's two scripts, `additionalDirectories`) plus the fixture's own commands (`npm test`, `make test`, `.venv/bin/pytest` …), which stand in for the owner choosing "don't ask again" on the first prompts.
- Hook trace: `DEV_TEAM_HOOK_LOG=<file>` (new) makes both guards append each hook input as one JSON line. The guard figures in §5 come from the tool results in the transcripts, not from replaying that trace.
- Not tested: an interactive session. It is unclear how a background subagent's permission requests and the Orchestrator's `AskUserQuestion` gates behave there (see §6).

Fixtures:

| Fixture | Stack | Start |
|---|---|---|
| `notes-node` | Node 22, Express 5, `node:test` + supertest, ESLint 9, npm, GitHub Actions | 1 commit, 5 tests |
| `tasks-flask` | Python 3.15 (CI 3.12), Flask 3.1, pytest, Ruff, pip + venv + Makefile, GitHub Actions | 1 commit, 5 tests |
| `greenfield-api` | Empty: a README only, no git | — |

## 2. Scenarios and results

| # | Project | Request | Size | Gates | Outcome |
|---|---|---|---|---|---|
| 1 | notes-node | `/health` returns the app version | S | 0, 1+2, 3 | Merged. The first run surfaced most of the permission findings in §4. It was resumed 6 times after fixes. |
| 2 | tasks-flask | Reject non-string titles | S | 0, 1+2, 3 | Merged, with no denials. Discovery could not run commands (`; echo $?`), so the Tester's run verified them. |
| 3 | notes-node | "Add authentication" | proposed M; the owner chose user accounts and upsized to L | 1+2 → upsize, 1, 2, 3 | Merged: 3 tasks, 25 ACs, 42 tests, 0 rework |
| 4 | tasks-flask | "Add authentication" | proposed L; the BA suggested smaller and the owner chose M | 1+2, 3 | Merged: 2 tasks, 13 ACs, 51 tests, 0 rework |
| 5 | greenfield-api | "Build a small REST API with login from scratch" | L | 1, 0 (+ `git init`), 2, 3 | M0 merged: 5 tasks, 30 tests. The profile is `decided` + `verified` and the roadmap shows M0 `done`. The run was interrupted by the account usage limit during T4 and resumed from `state.md` in a fresh session. |
| 6a | greenfield-api | Duplicate email → 409 | S | none | The Orchestrator found it already implemented and tested, and closed the run without calling an agent. |
| 6b | greenfield-api | `/health` returns the version from `pyproject.toml` | S | 1+2, 3 | Merged as **Established** (no discovery, no Gate 0). 32 tests. |

Every merge was `--no-ff`, followed by a `chore(team): update project knowledge` commit, with worktrees and branches removed and nothing pushed.

## 3. Cost per scenario

Tokens are input-token equivalents (`input + 1.25 × cache writes + 0.1 × cache reads + 5 × output`). The **subagent** columns come from each run's `state.md` usage log, which is what the budgets count. The **Orchestrator** column is summed from the main-session transcript with the same formula. `run-state.sh` does not count it (see §6).

| # | BA | Architect | Developer | Tester | Subagents total | Orchestrator | Notes |
|---|---|---|---|---|---|---|---|
| 1 S | — | 181,902 (haiku, discover) | 131,751 (3 calls, 2 blocked) | 121,429 (3 calls, 2 blocked) | 435,082 | 535,975 | Inflated by blocked calls |
| 2 S | — | 272,799 (haiku: discover 183,482 + improvised profile-update 89,317) | 73,253 | 67,574 | 413,626 | 304,999 | Clean run ≈ 324k; profile-update since removed from the brownfield flow |
| 3 L | 95,891 | 439,195 (opus: 170,660 discarded M design + 268,535 design) | 373,289 (3 tasks) | 220,406 (3 targeted) + 162,051 (haiku, full) | 1,290,832 | 697,649 | The upsize cost one discarded design call |
| 4 M | 65,880 | 163,256 (opus) | 190,835 (2 tasks) | 121,422 + 97,913 (haiku, full) | 639,306 | 531,656 | |
| 5 L (M0) | 56,050 | 543,092 (opus: propose 178,068, decide 74,420, design 290,604) | 601,342 (5 tasks + 1 lost to the interruption) | 426,242 (incl. verify-profile) | 1,626,726 | 949,799 (2 sessions) | 13 web lookups in the proposal |
| 6a S | — | — | — | — | 0 | 51,879 | No-op |
| 6b S | — | — | 85,686 | 73,991 | 159,677 | 190,960 | Established S baseline |

Observations:
- **S vs L.** An Established S run (6b) cost 12% of the brownfield L run (3) counting subagents, and 18% including the Orchestrator. The target is ≤ 25%: met. A first-run S includes Haiku discovery (~180k) and lands at ~25%.
- **Biggest single items.** The Opus design step (163–291k per call) and Haiku discovery (~180k). The Developer runs ~75–135k per task, and a targeted Tester call ~55–110k.
- **The Orchestrator is the hidden cost.** It adds 35–55% on top of the counted spend in every run, because its context grows with each turn, mostly through cache reads.
- **Resume is cheap.** Resuming the Developer to commit in place cost 24k, against 50–130k for a fresh Developer call.
- **Peak requests per agent call:** Architect 32 (`maxTurns` 40), BA 6 (20), Developer 20 (80 → **50**), Tester 11 (40 → **30**).
- **New default budgets** (subagent spend, in `run-state.sh` and the settings snippet): S 400k / 800k, M 1.0M / 2.0M, L 2.5M / 5M, down from 0.6M/1.2M, 1.5M/3M and 4M/8M. Each is set from one or two runs, so refine them at later retros.

## 4. Findings and fixes

Most findings concern how Claude Code's permission system treats background subagents, which cannot show a permission prompt: whatever needs approval is simply denied. Each fix below is in this commit.

| # | Finding | Fix |
|---|---|---|
| 1 | `pwd -P` is not read-only to the permission check; `$(…)`, `;` chains and shell variables always need approval | Orchestrator uses plain `pwd`; new *Plain shell commands* rule in `team-handoff` §2; Orchestrator ground rule 7 |
| 2 | `git -C <dir> …` always needs approval. `cd <dir> && git …` needs it whenever the `cd` changes directory (untrusted hooks or config) | Prompts use `cd <dir> && git …`; `guard-bash.sh` allows read-only git chains for every role, but only in the project's own repository (main checkout or its worktrees) |
| 3 | macOS has no `timeout` command, so every `timeout 600 <cmd>` exited 127 | Prompts use the Bash tool's own timeout |
| 4 | This build has no Grep or Glob tool. The BA (Read/Grep/Glob only) could not even list a directory | Rule: use grep, find and ls through Bash. The BA gets read-only Bash, guarded by a new `ba` role in `guard-bash.sh` |
| 5 | Permission checks resolve symlinks. With the symlink install, reading `~/.claude/dev-team/templates/…` needs the repo's real path allowed as well as the link path | Snippet `additionalDirectories` (install dir + skill dirs); `install.sh --with-settings` adds the repo's real path in link mode; `uninstall.sh` removes them |
| 6 | **The Orchestrator's frontmatter hooks also run for its subagents' tool calls** (`claude --agent orchestrator` makes them session hooks), so `guard-write.sh orchestrator` denied every Developer edit | Hook input carries `agent_id` and `agent_type`. The Orchestrator's guards make no decision for calls by `ba`/`architect`/`developer`/`tester`, which have their own guards |
| 7 | `acceptEdits` covers file edits, not `git add`/`commit`/`merge --ff-only`, so the Developer could not commit. Settings allow rules would also cover the owner's own sessions | `guard-bash.sh` allows a short per-role list of plain git steps (Developer and Tester in a linked worktree; Orchestrator init/merge/worktree remove/`branch -d` in the main checkout). Quoted text is neutralized, so commit trailers with `<…>` and multi-line messages pass; `$(`, backticks and unquoted operators or newlines never do |
| 8 | Output redirects need approval in `default` mode, so the Tester and Architect could not write logs | Architect and Tester use `permissionMode: acceptEdits`. `guard-bash.sh` keeps their shell writes (`rm`, `mv`, `cp`, `mkdir`, `touch`, redirects …) to `RUN_DIR/logs/` or temp dirs, checking the project first even when the project itself is under `/tmp` |
| 9 | `cd <dir> && <cmd> > file` (or `| tee file`) always needs approval, and a subagent's working directory does not persist between calls | The Tester pipes through `| tail -n 80` and saves failure evidence with Write. DoD: logs are required for failures only |
| 10 | Background agents cannot get approval for WebSearch or WebFetch, so the Architect's version checks failed | New `hooks/allow-web.sh` (Architect only): allows WebSearch and https WebFetch, capped at 15 per agent (`DEV_TEAM_WEB_LIMIT`) |
| 11 | `memory: project` writes `<project>/.claude/agent-memory/<role>/` in the main checkout (also for the worktree Developer); worktrees live in `.claude/worktrees/` | Agent memory is committed with the knowledge files. `run-state.sh new` and the new `run-state.sh exclude` (after greenfield `git init`) add `/.claude/worktrees/` to `.git/info/exclude` |
| 12 | The Orchestrator skipped creating `test-report.md` | Orchestrator §4 step 1 creates the step's files first. Any role creates a missing owned file from its template instead of stopping |
| 13 | Haiku discovery appended `; echo "exit=$?"` to every command, so all were denied | Rule: the Bash tool reports exit codes; never append `; echo $?` |
| 14 | The Orchestrator improvised an Architect `profile-update` in brownfield to mark commands verified | Orchestrator §8 step 3: copy the Tester's results itself |
| 15 | The new `learnings.md` was left uncommitted | §8 step 5 commits new or changed knowledge files (`git status --short .team .claude/agent-memory`) |
| 16 | The profile recorded volatile facts (test counts, single test files) that went stale after one feature | Discovery §2 step 8: record only what survives ordinary feature work |
| 17 | The Tester's guard refused read-only `git branch` | Allowed, except delete, move, copy and force forms |
| 18 | Retro playbook write denied: `guard-write.sh` compared a resolved target with the unresolved playbooks path | Compares with the resolved playbooks dir. The approved playbook `playbooks/python-fastapi.md` was added by hand |

## 5. Guard behavior (from the transcripts)

Real guard blocks across all scenarios: 8 by the Orchestrator's guard on Developer edits (#6), 2 on the playbook path (#18), 2 on the Tester's `git branch` (#17), and 1 correct block (the Tester appending to a test file with `cat >> … <<EOF`, which must go through Write). No false positives from patterns inside quoted strings, and no misses were observed, though no agent attempted a destructive or outward-facing command.

## 6. Exit criteria

| Criterion | Result |
|---|---|
| All scenarios complete with only gate approvals | **Partly.** Scenarios 2–6 needed only gate answers and the agents' `NEEDS_HUMAN` questions. Scenario 1 needed the fixes in §4 mid-run. Scenario 5 was interrupted by the account usage limit (external) and resumed from `state.md`. |
| Greenfield ends with a verified profile and a passing skeleton | **Met.** 30 tests; the server was started by hand at Gate 3 (`/health` 200, `/auth/register` 201). |
| A follow-up request on that project runs as Established | **Met** (6b) |
| Learnings written correctly | **Met.** Project entries in `learnings.md`, approved general rules in `~/.claude/agent-memory/orchestrator/` (passed on as `OWNER RULES` in a later project), approved stack rule in a playbook (after fix #18). |
| Every run stays within its hard budget | **Met** for counted (subagent) spend. The Orchestrator's spend is not counted. |
| An S run costs ≤ 25% of an L run | **Met:** 12% (18% with the Orchestrator) |
| Re-running one L scenario after the prompt fixes is no more expensive than its first run | **Not measured.** The L and M runs (3, 4, 5) already ran after the fixes that changed agent behavior (#1–#13). A re-run is the first thing to do in the prompt-tuning iteration. |

Open items carried forward:
- **Interactive mode is untested.** Check whether background agents' permission requests surface to the owner, and run the gates through `AskUserQuestion`.
- **Count the Orchestrator's spend in the budgets.** `run-state.sh` needs the main session's transcript path, which the Orchestrator does not know today.
- **Cross-project rules cost tokens.** An approved general rule ("re-fetch partial WebFetch pages") pushed the next stack proposal to 13 lookups. It was narrowed at the gate. Watch rule growth at retros.
- **Brownfield discovery commands still need allow rules** in the project (e.g. `npm ci`, `make install`). Without them, discovery records commands as `not run` and the Tester verifies them later.
