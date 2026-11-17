# dev-team-agents

A reusable multi-agent software team for [Claude Code](https://claude.com/claude-code): a Business Analyst, an Architect, a Developer and a Tester, coordinated by an Orchestrator.

You give the team a rough request. It analyzes, designs, implements and tests the work, and stops for your approval at defined gates. It works in two modes:

- **Greenfield:** in an empty directory, the team proposes a tech stack for you to approve.
- **Brownfield:** in an existing codebase, the team discovers the stack and conventions for you to confirm.

> **Status:** early development (Phase 4 done: orchestrator with modes, sizing, gates and budgets). Nothing is installable yet.

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
