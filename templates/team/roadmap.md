# Roadmap: <project name>

<!-- Owner: Architect (design step of the first greenfield run). The Orchestrator updates
     only the Status and Run columns. One milestone per run. -->

| ID | Goal | Covers | Status | Run |
|---|---|---|---|---|
| M0 | Walking skeleton | R<…> (one thin slice) | planned | |
| M1 | <…> | R<…> | planned | |

Status values: `planned` · `in-progress` · `done` · `dropped`

---

## M0: Walking skeleton

<!-- Always the first milestone. Fixed scope: no product features beyond one thin slice. -->

- **Scaffold:** project structure and repo layout as in the profile
- **Tooling:** install, build, lint, format, type check and test commands from the profile all work
- **CI:** pipeline runs lint and tests on every push
- **Thin slice:** <one end-to-end path through every layer, e.g. "GET /health reads from the database">
- **Exit criteria:** every command in the profile passes in CI and locally; the Tester has verified them

## M1: <goal>

- **Covers:** R<…>, AC<…>
- **Exit criteria:** <…>
- **Out of scope:** <…>

## Later

<!-- Requirements outside the MVP, not yet scheduled. -->
