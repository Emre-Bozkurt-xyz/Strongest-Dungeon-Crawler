---
name: strongest-dungeon-crawler-development
description: Default operating skill for any task inside the Strongest Dungeon Crawler codebase. Use this for all client/server/shared Roblox changes in this repo, including architecture, systems, UI, networking, combat, inventory, items, loot, and refactors. Use it to enforce repo-specific workflow: read core docs first, keep planning/progress files in docs/tasks during long work, validate via IDE/Luau diagnostics plus Roblox Studio playtests, and archive completed task docs to docs/archive.
---

# Strongest Dungeon Crawler Development

Use this skill as the baseline workflow for all work in this repository.

## Initial Read Order
Before making substantial changes, quickly scan these:

1. `docs/architecture/design-principles.md` (mandatory first read)
2. `docs/architecture-overview.md`
3. `docs/tasks/architecture-analysis.md`
4. `docs/tasks/architecture-analysis-checklist.md`
5. Active task docs relevant to request:
   - `docs/tasks/items.md`
   - `docs/tasks/ui-progress.md`
   - `docs/tasks/projectile-system-revival.md`

If docs conflict with code, trust code and update docs as part of task completion.

## Design Principles First
`docs/architecture/design-principles.md` is the governing architecture document for this repo.

Treat it as a hard constraint, not optional guidance:

- use it to choose module boundaries and ownership
- use it to reject quick fixes that increase coupling or hidden state
- use it to keep systems traceable, predictable, and refactor-friendly

If implementation pressure conflicts with design principles, pause and record the tradeoff in the active `docs/tasks/*.md` file before proceeding.

## Repo Workflow (Mandatory)

### 1) Scope and plan
For any task longer than a quick fix:

- Create or reuse a task file in `docs/tasks/`:
  - `docs/tasks/<topic>.md`
- Keep these sections up to date:
  - Goal
  - Current decisions
  - TODO checklist
  - Validation plan
  - Results/notes

### 2) Context hygiene for long tasks
- Keep only active context in the current task doc.
- Move completed/obsolete notes to `docs/archive/`.
- Do not let stale plan docs keep conflicting decisions alive.

### 3) Implementation style
- Prefer explicit, deterministic behavior over hidden fallbacks.
- For required config/contract data, fail fast with clear errors instead of silent fallback behavior.
- Keep ownership boundaries clear:
  - controllers own controller logic
  - services own service logic
  - shared modules define contracts/types/protocols
- Avoid adding cross-system coupling in core modules (especially camera/UI/system coupling).

### 4) Update docs with code
At the end of meaningful implementation:

- Update the active task doc with what changed and why.
- Mark checklist items complete/incomplete explicitly.
- If a phase/task is verified complete, archive its working notes to `docs/archive/`.

## Testing and Validation Rules (Repo-Specific)

This project is validated primarily in Roblox Studio by the developer.

- Assume no full compile/test pipeline is available.
- Primary checks:
  - Luau type diagnostics (IDE)
  - Selene/lint diagnostics (IDE)
  - Runtime logs in Roblox Studio
  - Manual gameplay verification by developer

When handing off changes:

1. Provide a short Studio playtest checklist.
2. Ask for exact console output for any runtime issue.
3. Use logs to drive targeted fixes, not speculative band-aids.

## Recommended Change Sequence
When touching a system:

1. Read call sites and ownership boundaries.
2. Identify state owner and data flow.
3. Make the smallest coherent structural change first.
4. Validate with IDE errors + Studio run.
5. Iterate with explicit logging only where needed; remove noisy temp logs after verification.

## Roblox Skill Reference
Use `.agents/skills/roblox-game-development/SKILL.md` as secondary guidance for:

- reusable Roblox implementation patterns
- networking/data/UI design best practices
- performance and debugging practices

Do not copy generic patterns blindly; adapt to this repo's architecture and constraints.

## Output Expectations for This Repo
- Always include:
  - files changed
  - behavior change summary
  - what to verify in Studio
  - known risks or follow-up work
- Keep recommendations practical and scoped to current architecture stage.

## Definition of Done (Per Task/Phase)
A task is done when all are true:

1. Code behavior matches agreed decision.
2. No known unresolved critical Luau/Selene errors in changed paths.
3. Developer confirms Studio behavior.
4. Task doc is updated.
5. Completed task notes are archived when appropriate.
