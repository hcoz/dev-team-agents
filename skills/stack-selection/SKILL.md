---
name: stack-selection
description: Propose a tech stack for a new (greenfield) project - 2-3 options justified against the approved requirements, one recommendation, every version checked against official sources - and write .team/stack-decision.md. After the owner decides at Gate 0, record the decision and derive the planned project-profile.md. Use as the Architect in a greenfield run.
---

# Stack selection

Inputs from the Orchestrator: `PROJECT`, `RUN_DIR`, and a step: `propose` or `decide`. You write only `$PROJECT/.team/stack-decision.md` and, in the `decide` step, `$PROJECT/.team/project-profile.md`. Both start from the templates.

## Step `propose` (before Gate 0)

1. **Read the drivers.** Read `$RUN_DIR/requirements.md`, which must be approved. Pull out what decides the stack: must-have requirements, non-functional requirements (load, latency, offline use, compliance), the *Stack constraints* section (languages the owner knows, hosting and budget, must use or avoid), and the deadline. Write them to *Drivers* with their IDs. If a constraint that would change the choice is missing, return `NEEDS_HUMAN` with a question and options. Do not assume an answer.
2. **Check the evidence.** Read `~/.claude/dev-team/playbooks/*.md` for stacks this owner has used before, and your user memory. Record what you find under *Owner history* for each option.
3. **Build 2–3 options.**
   - **Option A is always the simplest stack that meets the requirements:** the fewest moving parts, in a language the owner knows where possible.
   - Option B trades something real against A, such as scalability, a different ecosystem or managed services. Add Option C only if it differs materially from both.
   - Prefer mainstream, actively maintained tools (a release in the last 12 months) and LTS runtimes.
   - Add no components the requirements do not need: no microservices, queues, Kubernetes or separate frontend apps unless a requirement calls for them.
4. **Check versions.** Never write a version from memory.
   - For the **recommended** option, check every component against an official source: release page, official docs or the package registry. For the other options, the major version is enough.
   - Budget: about **10 web lookups** in total. Official sources come first. Package-manager queries (`npm view <pkg> version`, `pip index versions <pkg>`, `go list -m -versions <mod>`) are cheaper and count as lookups too.
   - Record version, source URL and the date you checked. If a version cannot be verified, write `unverified` and say why.
5. **Compare.** Fill in the *Comparison* table: requirement fit (by ID), owner familiarity, simplicity, hosting and running cost, ecosystem maturity, testability, and time to the walking skeleton. Use short words, not scores.
6. **Recommend** one option. Say why in 2–4 lines, and name the condition that would change your recommendation.
7. **Fill in *Recommended stack in detail*:** language and runtime, framework, database, package manager, test tooling, lint and format, CI, deployment target, repo layout.
8. **Reply** using the hand-off format. In the summary, give the options in one line each and the recommendation. Status: `DONE`.

## Step `decide` (after Gate 0)

The Orchestrator resumes you with the owner's answer: an option, possibly with changes.

1. **Record the decision.** Fill in the *Decision* section and set `Status: approved`. If the owner changed a component, check its version (step 4) and update *Recommended stack in detail*.
2. **Derive the profile** from `stack-decision.md`:
   - `Origin: decided`. Leave `Status: draft`: the Orchestrator sets it to `planned`.
   - Fill in Stack, Layout (the planned repo layout), Commands and conventions from the chosen stack's standard tooling and any matching playbook. Mark every command as Verified `not run`.
   - Leave the fingerprint block empty: it is written after M0 is merged.
   - The Developer will scaffold to match this profile, and the Tester will verify every command during M0.
3. **Reply** using the hand-off format. Status: `DONE`. The design step (roadmap, design, M0 tasks) follows as a separate call.
