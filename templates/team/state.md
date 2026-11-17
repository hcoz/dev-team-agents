# Run state: <run-id>

<!-- Owner: Orchestrator (sole writer). Source of truth when resuming a run. -->

| Field | Value |
|---|---|
| Run ID | <YYYY-MM-DD-slug> |
| Request | <one line, as given by the owner> |
| Created | <YYYY-MM-DD HH:MM> |
| Mode | greenfield · brownfield · established |
| Size | S · M · L (proposed: <x>; confirmed by owner: yes/no) |
| Milestone | <M0, M1 … for roadmap runs; otherwise n/a> |
| Current step | <e.g. design · implement T2 · test T2 r1 · gate 3> |
| Status | active · waiting-for-owner · blocked · done · aborted |

## Scope note

<!-- S runs only; replaces requirements.md and design.md. Otherwise n/a. -->

- **Change:** <what to change>
- **Where:** `<path>` — <why>
- **Acceptance criteria:**
  - AC1: <testable outcome>
- **Out of scope:** <…>

## Code

<!-- Run base: the default-branch commit the run started from. One row per Developer call that made a worktree.
     A later task's fresh Developer starts from the previous task's head (START_FROM), so its Base is that head.
     The last row's branch holds the whole run and is the one merged at Gate 3. -->

| Field | Value |
|---|---|
| Default branch | <main> |
| Run base | <sha> |

| Task | Developer agent ID | Worktree | Branch | Base | Head |
|---|---|---|---|---|---|

## Gates

<!-- S and M runs: record the merged Gate 1+2 on row 1 and write "merged into 1" on row 2. -->

| Gate | Result | Date | Notes |
|---|---|---|---|
| 0 Stack | pending · approved · changed · n/a | | |
| 1 Requirements | pending | | |
| 2 Design | pending | | |
| 3 Merge | pending | | |

## Rework counters

Caps: 3 rounds per task, 8 per run.

| Task | Rounds |
|---|---|
| **Run total** | 0 |

## Budget

<!-- Written by run-state.sh. Tokens are input-token equivalents, summed from the subagent transcripts and
     the Orchestrator's own session transcript(s): input + 1.25 × cache writes + 0.1 × cache reads + 5 × output.
     Roughly proportional to cost on one model. Spent so far = Subagents + Orchestrator; the budgets apply to it. -->

| | Tokens |
|---|---|
| Soft budget | <from profile, settings or defaults> |
| Hard budget | <from profile, settings or defaults> |
| Spent so far | 0 |
| Subagents | 0 |
| Orchestrator | 0 |
| Soft budget acknowledged | no |

## Usage log

<!-- One row per agent call, plus one "orchestrator" row per Orchestrator session (keyed by the session ID's
     first 8 characters), which run-state.sh updates in place as the run goes on. -->

| # | Time | Agent | Agent ID | Step | Model | Tokens | Duration | Rework round | Status |
|---|---|---|---|---|---|---|---|---|---|

## Owner decisions

<!-- Every NEEDS_HUMAN question and gate decision, in order. -->

| # | Asked by | Question | Answer |
|---|---|---|---|

## Candidate learnings

<!-- Collected from the Learnings section of each agent reply; classified at the retro. -->

| # | From | Learning | Class (project · general · drop) |
|---|---|---|---|
