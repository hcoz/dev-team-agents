# Playbooks

One file per stack, e.g. `python-fastapi.md` or `node-nextjs.md`. Playbooks grow through the retro, and only with the owner's approval. They are read by:

- **discovery**, to know what to look for in a project on this stack;
- **stack selection**, as evidence of what has worked for this owner.

File names: lowercase `<language>-<framework>.md`; use `<language>.md` for advice that applies to the whole language.

## Format

```markdown
# <Stack name>

Last updated: <YYYY-MM-DD>

## Discovery hints
- <where commands and config usually live; what to check>

## Default commands
| Purpose | Command | Notes |
|---|---|---|

## Conventions that worked
- <rule> (<project>, <date>)

## Pitfalls
- <what failed> → <what fixed it> → <rule> (<project>, <date>)

## Used in
- <project> — <date> — <outcome>
```
