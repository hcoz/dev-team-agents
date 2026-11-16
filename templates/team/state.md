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

| Field | Value |
|---|---|
| Worktree | <absolute path> |
| Branch | <branch> |
| Base commit | <sha the branch started from> |
| Head commit | <sha after the last Developer or Tester commit> |

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

| | Tokens |
|---|---|
| Soft budget | <from settings or profile> |
| Hard budget | <from settings or profile> |
| Spent so far | 0 |

## Usage log

| # | Time | Agent | Step | Model | Tokens | Duration | Rework round | Status |
|---|---|---|---|---|---|---|---|---|

## Owner decisions

<!-- Every NEEDS_HUMAN question and gate decision, in order. -->

| # | Asked by | Question | Answer |
|---|---|---|---|

## Candidate learnings

<!-- Collected from the Learnings section of each agent reply; classified at the retro. -->

| # | From | Learning | Class (project · general · drop) |
|---|---|---|---|
