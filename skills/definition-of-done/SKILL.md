---
name: definition-of-done
description: Generic definition of done for a dev-team task - what must be true before the Developer hands a task to the Tester, and before the Tester passes it to Gate 3. Extended per project by the commands, conventions, risky areas and promoted rules in .team/project-profile.md. Use as the Developer or the Tester.
---

# Definition of done

A task is done when every item below holds. The project profile extends this list: its commands are the checks, and its *Code conventions*, *Promoted rules* and *Risky areas* are rules too. Where the profile is stricter, the profile wins.

## Developer: ready for test

1. **Scope.** Every *Done when* item of the task (S: every acceptance criterion in the scope note) is met. Nothing outside the task's scope changed, except what you name in your summary with a reason.
2. **Design.** The code follows `design.md`. Any deviation is listed in your summary, so the Architect can record it under *Deviations*.
3. **Tests.** New or changed behavior has tests at the level `design.md` names (S: at least one test per acceptance criterion where the stack allows it). Existing tests are not deleted or weakened to make them pass.
4. **Checks pass** using the profile's commands, in your worktree: format check, lint, type check, and the targeted tests for the files you touched. Do not run the full suite: the Tester does that once, before Gate 3.
5. **No new warnings** from these checks in the files you touched.
6. **Conventions.** Names, layout, error handling and logging match the profile and the surrounding code.
7. **Risky areas.** You followed each rule in the profile's *Risky areas* (for example: a new migration instead of an edited one, regenerated code instead of hand edits).
8. **Hygiene.** No secrets, credentials or `.env` values in code, tests, logs or commits. No debug output, commented-out code or stray TODOs without a task ID. New dependencies are the ones `design.md` names, pinned the way the project pins them, with the lock file updated by the package manager.
9. **Commits.** All work is committed on your branch in the worktree, in the profile's commit style. `git status --porcelain` is empty.

## Tester: ready for Gate 3

1. **Acceptance.** Every acceptance criterion in scope has a result in `test-report.md`: `pass`, or `fail` with a finding. `not tested` is allowed only with a reason the owner can judge.
2. **Full suite.** The profile's full test suite, lint and type check ran once on the final head commit and passed, or every failure is a finding.
3. **No regressions.** A test that passed on the base commit and fails on the head is always a finding, even when it is outside the task's area.
4. **Findings closed.** No `blocker` or `major` finding is `open`. A `minor` finding may stay open only when the report says why.
5. **Evidence.** Each result points to a test name, a command and a log file in `RUN_DIR/logs/`.
6. **Profile commands** (greenfield M0): every command in the profile ran, and the report's *Commands run* table has one row per profile command with its result and duration. The profile's *Verified* column is updated from that table; the profile becomes `verified` only when every row passes.
