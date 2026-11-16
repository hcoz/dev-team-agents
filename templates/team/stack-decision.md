# Stack decision: <project name>

<!-- Owner: Architect (stack-selection skill). Greenfield only. Approved at Gate 0.
     Kept in the repo as the decision record. -->

| Field | Value |
|---|---|
| Status | draft · approved |
| Date | <YYYY-MM-DD> |
| Based on | `runs/<run-id>/requirements.md` (approved <date>) |

## Drivers

<!-- The requirements and constraints that decide the choice, with their IDs. -->

| Driver | Source | Why it matters for the stack |
|---|---|---|
| <e.g. owner knows TypeScript> | stack constraints | <…> |
| <e.g. 50 concurrent users> | NFR | <…> |

## Options

<!-- 2–3 options. Option A is always the simplest stack that meets the requirements. -->

### Option A: <name> (simplest)

- **Summary:** <one line>
- **Components:** <language/runtime · framework · database · hosting>
- **Fits the requirements:** <by ID>
- **Pros:** <…>
- **Cons:** <…>
- **Owner history:** <playbook or past project evidence; or none>

### Option B: <name>

<same fields>

### Option C: <name> (optional)

<same fields, only if materially different from A and B>

## Comparison

| Criterion | A | B | C |
|---|---|---|---|
| Meets requirements | | | |
| Owner familiarity | | | |
| Simplicity (moving parts) | | | |
| Hosting and running cost | | | |
| Ecosystem maturity | | | |
| Testability | | | |
| Time to walking skeleton | | | |

## Recommendation

**Option <X>.** <why, in 2–4 lines>

**Would change if:** <the condition that would flip the recommendation>

## Recommended stack in detail

<!-- Every version is checked against an official source. Never from memory. -->

| Area | Choice | Version | Source (checked <date>) |
|---|---|---|---|
| Language / runtime | | | <URL> |
| Framework | | | |
| Database | | | |
| Package manager | | | |
| Test tooling | | | |
| Lint / format | | | |
| CI | | | |
| Deployment target | | | |
| Repo layout | | n/a | |

## Decision

<!-- Filled after Gate 0 with the owner's answer. -->

- **Chosen:** <option, or option with changes>
- **Changes from the recommendation:** <none · list>
- **Owner's reason:** <if given>
- **Date:** <YYYY-MM-DD>

## Consequences

<!-- What this choice commits the project to; what becomes harder later. -->
