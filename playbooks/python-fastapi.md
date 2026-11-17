# Python + FastAPI

Last updated: 2026-11-17

## Discovery hints
- Dependencies and tool config live in `pyproject.toml` (runtime pins plus a `dev` extra); there is no lock file with plain pip, so the exact `==` pins are the reproducibility contract.
- Check that every native dependency (pydantic-core, argon2-cffi-bindings) ships a wheel for the local CPython version before recommending that version.

## Default commands
| Purpose | Command | Notes |
|---|---|---|
| Install | `python3 -m venv .venv` then `.venv/bin/python -m pip install -e '.[dev]'` | No uv needed |
| Lint | `.venv/bin/ruff check .` | |
| Format check | `.venv/bin/ruff format --check .` | |
| Tests | `.venv/bin/pytest` | In-process via FastAPI `TestClient` (needs httpx) |
| Run locally | `.venv/bin/uvicorn app.main:app --port 8000` | Cannot be verified from a sandboxed Tester: the owner checks it by hand |

## Conventions that worked
- Declare dependencies as `Annotated[T, Depends(...)]` instead of a default argument with `# noqa: B008`: Ruff's B008 flags the default-argument form (greenfield-api, 2026-11-17).

## Pitfalls
- Tester tried to start uvicorn to verify *Run locally* → the sandbox refused to bind a port → the owner verified it by hand at Gate 3; the profile records it as verified by the owner (greenfield-api, 2026-11-17).

## Used in
- greenfield-api (e2e dry-run) — 2026-11-17 — M0 walking skeleton merged, profile verified, 30 tests
