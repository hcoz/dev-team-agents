# Project profile: <project name>

<!-- Owner: Architect (discovery, or derived from stack-decision.md).
     The Orchestrator writes only: the Status field, the Fingerprint block (via stack-scan.sh write)
     and "Promoted rules" (at the retro). Every agent reads this file before acting and uses
     the commands below instead of guessing. -->

| Field | Value |
|---|---|
| Status | draft |
| Origin | <discovered · decided> |
| Last discovery | <YYYY-MM-DD> · <full · incremental> · <run-id> |
| Profile version | 1 |

<!-- Status: draft (written, not yet approved at Gate 0) · planned (greenfield: stack approved, M0 not verified)
     · verified (commands proven and approved). -->

## Stack

<!-- One row per package or app in a monorepo; one row otherwise. -->

| Area / package | Path | Language + version | Framework(s) + version | Package manager |
|---|---|---|---|---|
| <app> | `.` | <…> | <…> | <…> |

## Layout

- **Repo type:** single package · monorepo (<workspaces / tool>)
- **Key directories:**
  - `<path>` — <purpose>

## Commands

<!-- Exact commands, copy-pasteable. "Verified" = an agent ran it and it passed.
     The targeted-test row must show how to run one file or one test: the Tester relies on it. -->

| Purpose | Command | Working dir | Verified | Duration | Notes |
|---|---|---|---|---|---|
| Install | `<…>` | `.` | yes <date> · failed · not run | | |
| Build | | | | | |
| Run locally | | | | | |
| Lint | | | | | |
| Format check | | | | | |
| Format fix | | | | | |
| Type check | | | | | |
| Unit tests (all) | | | | | |
| Targeted test | `<cmd> <path-or-pattern>` | | | | |
| Integration tests | | | | | |
| E2E tests | | | | | |

## Environment and services

<!-- Env var NAMES only, never values. Local services (database, queue) and how to start them. -->

- **Env vars:** <NAME — purpose — where it is set (e.g. .env.example)>
- **Services:** <e.g. postgres via `docker compose up -d db`>
- **Setup steps:** <one-time steps beyond Install>

## Test conventions

- **Frameworks:** <…>
- **Location and naming:** <e.g. `tests/test_<module>.py`, colocated `*.test.ts`>
- **Fixtures and mocks:** <…>
- **Coverage expectations:** <if any>

## Code conventions

- **Style and formatting:** <tools and notable settings>
- **Structure:** <module layout, layering rules>
- **Naming:** <…>
- **Error handling and logging:** <…>

### Promoted rules

<!-- Stable rules promoted from learnings.md at the retro. -->

## Git conventions

- **Default branch:** <main>
- **Commits:** <e.g. Conventional Commits>
- **Branches:** <e.g. feat/<slug>>
- **Pull requests:** <template, required reviews, checks>

## CI

- **Provider and files:** <e.g. GitHub Actions, `.github/workflows/ci.yml`>
- **On pull request:** <jobs and the commands they run>
- **Required checks:** <…>

## Risky areas

| Area | Path | Rule |
|---|---|---|
| <e.g. migrations> | `<path>` | <e.g. new migration only, never edit applied ones> |
| <e.g. generated code> | `<path>` | <never edit; regenerate with `<cmd>`> |
| <e.g. secrets> | `<path>` | <never read or print values> |

## Budget overrides

<!-- Optional. Overrides the default token budgets from settings for this project. -->

| Size | Soft | Hard |
|---|---|---|
| S | default | default |
| M | default | default |
| L | default | default |

## Open issues

<!-- Commands that failed, unknowns, things the owner must confirm at Gate 0. -->

## Change log

| Date | Change | Run |
|---|---|---|

## Fingerprint

<!-- Written by `stack-scan.sh write`. Never edit by hand. -->

<!-- fingerprint:begin -->
<!-- fingerprint:end -->
