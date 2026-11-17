---
name: project-discovery
description: Detect the run mode (greenfield, brownfield, established) and build or refresh .team/project-profile.md for an existing codebase - languages, frameworks, package managers, exact install/build/lint/test commands, conventions, CI and risky areas - plus the fingerprint used to detect a stale profile. Use as the Orchestrator when starting a run, or as the Architect when asked to discover or re-discover a project.
---

# Project discovery

`stack-scan` below means `~/.claude/skills/project-discovery/scripts/stack-scan.sh` (this skill's `scripts/` folder). It does the mechanical parts — mode detection, fingerprints, staleness — so you never compute or copy hashes by hand.

## 1. Mode detection (Orchestrator, first step of every run)

Run `stack-scan mode "$PROJECT"` and act on its `mode:` line:

| `mode:` | Meaning | Next step |
|---|---|---|
| `established` | Profile `verified` | Act on the `status:` line (§4) |
| `brownfield` | Build manifest found, no profile | Full discovery (§2), then Gate 0 |
| `greenfield` | No profile: only docs, notes, licenses. Or profile `planned`: the stack is approved but M0 is not verified | No profile: BA, then stack selection. `planned`: continue at the roadmap's current milestone |
| `resume` | Profile `draft`: an earlier run stopped before Gate 0 | Resume that run from its `state.md`, or re-run discovery if there is none |
| `ambiguous` | Files that are not docs, but no manifest; or an unknown profile status | Ask the owner, listing the `file:` lines |

- The owner's explicit instruction ("treat this as greenfield") overrides the detected mode.
- `git:` line: `none` or `no-commits` means git must be initialized with an initial commit before the Developer starts (ask the owner first). `parent-repo <path>` means the project sits inside another repo; ask the owner before going on.
- Record the mode and the `git:` result in `state.md`. Show both at the first gate.

## 2. Full discovery (Architect)

Inputs from the Orchestrator: `PROJECT`, `RUN_DIR`, scope `full`. You write only `$PROJECT/.team/project-profile.md` (from the template) and logs. Never edit source code, configuration or lock files.

1. **Map the repo.** `cd <PROJECT> && git ls-files | head -200`, a depth-2 directory listing, and `stack-scan fingerprint "$PROJECT"`. The fingerprint lists every file that defines the stack, by category.
2. **Check the playbooks.** For each detected stack, read `~/.claude/dev-team/playbooks/<stack>.md` if it exists. It lists what to look for and known pitfalls.
3. **Stack.** From the manifests and toolchain files, record languages and runtime versions, frameworks with versions, and the package manager. The lock file decides the package manager (`pnpm-lock.yaml` means pnpm, `uv.lock` means uv, and so on). For a monorepo, add one row per app or package and name the workspace tool.
4. **Commands.** Take them from these sources, in this order:
   1. the CI workflow steps (what actually runs);
   2. task runners: `package.json` scripts, Makefile, justfile, tox or nox, Taskfile;
   3. README and CONTRIBUTING;
   4. tool defaults from the playbook.

   Record each command exactly, with its working directory. For tests, record both the full-suite command and the **targeted** form (one file or one test), because the Tester relies on the targeted form. Note the services and env var *names* that tests need (never read secret values; only note that `.env` files exist).
5. **Conventions.** Read 3–5 existing tests and a few typical source files for layout, naming, fixtures and error handling. Run `git log --oneline -30` and `git branch -a` for commit and branch conventions. Read the PR template if there is one.
6. **Risky areas.** Look for migrations, generated code (note the command that regenerates it), secrets and `.env*` files, vendored code, infrastructure files and public API contracts.
7. **Verify.** Run `git status --porcelain` first. Then run each recorded command once, in this order: install → build → lint → type check → targeted test → full test suite. Set the Bash tool's timeout to 600000 ms for each (there is no `timeout` command on macOS). Send output to `RUN_DIR/logs/architect-discover-r0.log`, and record the result and duration in the *Verified* column.
   - Only run commands that are safe. A safe command does not modify tracked files and does not touch remote systems: no deploys, no migrations against non-local databases, no publishing. For install, prefer the frozen or lockfile form (`npm ci`, `pnpm install --frozen-lockfile`, `uv sync --frozen`, `bundle install` with frozen mode).
   - Mark any command you skipped as `not run`, with the reason.
   - If `git status --porcelain` shows a change after a command, stop running commands. Do not revert anything. Record the change under *Open issues* and report it.
8. **Write the profile.** Record only what stays true across ordinary feature work: directories and patterns, not single test files; commands, not test counts or timings beyond a rough duration. Set `Origin: discovered` and leave `Status: draft`, because the Orchestrator sets it after Gate 0. Put failed commands and open questions under *Open issues*. Fill in `Last discovery` and add a *Change log* row. Then run `stack-scan write "$PROJECT/.team/project-profile.md" "$PROJECT"`.
9. **Reply** using the hand-off format. List any failed or skipped commands in the summary.

## 3. Incremental re-discovery (Architect)

Inputs: scope `incremental`, plus the `check` output (the `areas:` line and the changed files). Re-check only the profile sections those files affect:

| Category | Re-check |
|---|---|
| `manifest` | Stack rows; commands defined in that manifest (scripts, test config); Layout if packages were added or removed |
| `lock` | Package manager and pinned framework versions |
| `toolchain` | Runtime versions |
| `build` | Build, run, test and service commands and the environment |
| `lint` | Lint, format and type-check commands and the style conventions |
| `ci` | The CI section and the commands CI runs |

Re-run only the affected commands (§2 step 7). Update only the affected sections. Add a *Change log* row per change, then run `stack-scan write`. Leave `Status` as it is. In your summary, list the old → new value for every changed command or version: that list is what Gate 0 shows.

## 4. Staleness rule (Orchestrator)

When the mode is `established`, read the `status:` line:

| `status:` | Action | Gate 0 |
|---|---|---|
| `fresh` | Nothing to do | No |
| `lock-only` | Run `stack-scan write`. Mention it at the first gate | No |
| `stale` | Incremental re-discovery of the listed `areas:`, using the cheap model | Yes, showing only the changes |
| `layout` | A root manifest was added or removed: full re-discovery | Yes, full |
| `missing` | The profile has no fingerprint: full re-discovery | Yes, full |

The owner can ask for full re-discovery at any time.
