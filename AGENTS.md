# Better-Nexus agent instructions

Before implementation or review, read `CONTRIBUTING.md` and `AI_POLICY.md`. For package or release work, also read `RELEASE_SECURITY.md`; for vulnerability handling, read `SECURITY.md`.

Preserve Lua 5.1, WoW 3.3.5a / Project Ebonhold compatibility, the `Nexus` runtime identity, and SavedVariables compatibility. For native API or UI changes, consult the exact versioned client/export reference when authorized; see the native-contract rules in `docs/agents/domain.md`.

Use an isolated checkout for overlapping work. Coordinate candidate ownership and preserve commits already under review or native testing. Record validation against the final source pin, keep unavailable checks explicit, and distinguish offline results from native evidence. Existing review, tester-delivery and release gates remain in force.

## Agent skills

### Engineering workflow

Use the installed Matt `implement`, `tdd` and `code-review` flows when relevant; their availability does not prove that a worker read or followed them. Start from the current issue or spec and keep one small vertical slice in scope. For behavioral changes, establish a meaningful failing test before the repair where practical, then run focused checks and the required full suite against the final source pin. Do not invent a behavioral red test for documentation-only work or weaken an assertion to obtain green.

Review from a pinned base along independent **Spec** and **Standards** axes before acceptance. Cite the originating requirements and documented repository rules separately; keep heuristic design advice distinct from hard violations. Preserve failed checks and report unavailable validation honestly. Existing merge, native and release authority still governs the next action.

### Issue tracker

Durable public work is tracked in GitHub Issues for `Viscerals/Better-Nexus`. Read `docs/agents/issue-tracker.md` before tracker work.

### Triage labels

Reuse the existing five-state mapping, including `needs-info` → `needs-diagnostics`. Read `docs/agents/triage-labels.md` before triage.

### Domain docs

Single-context: root `CONTEXT.md` for the glossary and `docs/adr/` for decisions, created when needed. Read `docs/agents/domain.md` before domain or design work.

## Working updates

Read `docs/agents/reporting.md` for the shared Claude/Codex progress, important-context, impact and learning practices.
