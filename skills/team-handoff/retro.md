# Retro and learnings protocol (Orchestrator)

The retro turns the candidate learnings from agent replies into lasting knowledge. It is not a separate agent call: the Orchestrator does it at the end of a run, after Gate 3 or after an abort.

**Skip it** for an S run when no agent reported a candidate learning.

## Steps

1. **Collect.** Take the *Candidate learnings* table in `state.md`. It is filled from each reply's *Learnings* section as the run goes.
2. **De-duplicate.** Drop candidates already covered by `learnings.md` or by the profile's conventions or *Promoted rules*.
3. **Classify** each remaining candidate:

   | Class | Test | Goes to |
   |---|---|---|
   | `project` | Only true for this codebase | `.team/learnings.md` |
   | `stack` | True for any project on this stack | `~/.claude/dev-team/playbooks/<stack>.md` |
   | `general` | True for any project | user-level memory |
   | `drop` | One-off, already known, or not actionable | nowhere |

4. **Write the project learnings.** Append the `project` items to `learnings.md` in the entry format from its header. They do not need approval, but list them in the run's final report.
5. **Promote with approval.** Show the `stack` and `general` items to the owner in a single multi-select question. Write only the approved ones:
   - `stack` items go into the matching playbook, which is created from `playbooks/README.md` if it does not exist yet. Do not commit in the dev-team-agents repo; give the owner the changed paths.
   - `general` items go into user-level memory.

   Nothing reaches cross-project scope without the owner's approval.
6. **Compact** when `learnings.md` has more than ~150 lines of entries. Aim for at most ~100 lines afterwards:
   - merge duplicates and near-duplicates into one entry;
   - drop entries that no longer apply (the code or tool is gone, or a later entry replaced them);
   - promote stable rules (seen in 2 or more runs, or confirmed by the owner) to *Promoted rules* in `project-profile.md`, and remove them from `learnings.md`;
   - add a row to the *Compaction log*.
7. **Commit** only with the owner's Gate 3 approval, together with the change. Commit the changed project-level knowledge files: `project-profile.md`, `stack-decision.md`, `roadmap.md`, `learnings.md`. Never commit `.team/runs/`. Never push.
