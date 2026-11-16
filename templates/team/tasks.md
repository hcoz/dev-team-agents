# Tasks: <run-id>

<!-- Owner: Architect. The Orchestrator updates only the Status column.
     Each task fits in one Developer call and one Tester check. Table order = execution order. -->

| ID | Title | Status | Depends on |
|---|---|---|---|
| T1 | <…> | todo | — |

Status values: `todo` · `in-progress` · `in-test` · `rework` · `done` · `blocked`

---

## T1: <title>

- **Covers:** R1, AC1
- **Files to touch:**
  - `<path>` — <what changes>
- **Entry points:** `<path>:<symbol>` — <where to start reading>
- **Relevant tests:**
  - existing: `<path>`
  - new: `<path>` — <what it checks>
- **Done when:** <observable result, tied to the ACs>
- **Notes:** <constraints, pitfalls; or none>
