# dev-team-agents

A reusable multi-agent software team for [Claude Code](https://claude.com/claude-code): a Business Analyst, an Architect, a Developer and a Tester, coordinated by an Orchestrator.

You give the team a rough request. It analyzes, designs, implements and tests the work, and stops for your approval at defined gates. It works in two modes:

- **Greenfield:** in an empty directory, the team proposes a tech stack for you to approve.
- **Brownfield:** in an existing codebase, the team discovers the stack and conventions for you to confirm.

> **Status:** early development (Phase 6 done: end-to-end dry-runs, see [docs/e2e-dry-run-notes.md](docs/e2e-dry-run-notes.md)). Validated headless on Node and Python projects and one greenfield project.

## Install

Requires Claude Code 2.1.295 or later, `git`, and `jq` or `python3`.

```sh
git clone <this repo> && cd dev-team-agents
scripts/install.sh                  # symlinks into ~/.claude (use --copy to copy instead)
scripts/install.sh --with-settings  # also merge default budgets, script allow rules and the install's directories into ~/.claude/settings.json
```

Use `--with-settings` unless you add the same entries yourself. The team's subagents run in the background and cannot ask for permission, so without `additionalDirectories` they cannot read the templates and playbooks. For the same reason, approve each project's install, lint and test commands once ("don't ask again") or add allow rules for them in the project's `.claude/settings.local.json`.

Then, in a project directory: `claude --agent orchestrator`. Anything the installer would overwrite is moved to `~/.claude/dev-team-backups/` first. `scripts/uninstall.sh` reverses the install and restores those files. Both scripts take `--dry-run`.

## Layout

| Path | Contents |
|---|---|
| `agents/` | Agent definitions: orchestrator, ba, architect, developer, tester |
| `skills/` | Shared skills: hand-off contract, project discovery, stack selection, definition of done |
| `playbooks/` | Stack-specific lessons that accumulate over time |
| `hooks/` | Guard hooks for shell commands and file writes |
| `templates/team/` | Skeletons for the `.team/` state files created in target projects |
| `settings/` | Optional settings snippet: permissions, default cost budgets |
| `scripts/` | `install.sh` / `uninstall.sh` |
| `docs/` | Implementation plan and design decisions |

## Plan

See [docs/implementation-plan.md](docs/implementation-plan.md).

## License

[MIT](LICENSE)
