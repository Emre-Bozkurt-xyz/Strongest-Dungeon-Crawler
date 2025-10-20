# Stats & Attributes Refactor Plan

## Goals
- Adopt a mediator-centric pipeline that caches modifiers per stat and invalidates on mutation.
- Replace ad-hoc arithmetic with explicit operation strategies for clarity and controllable stacking.
- Standardize timed modifier lifecycle with shared countdown timers and disposal events.
- Provide factories/registries so gameplay systems request modifiers by intent instead of implementation detail.
- Surface stat change events for UI/FX/analytics consumption and future replay logging.

## Phase 0 – Discovery & Hardening
- [x] Inventory current stats, attributes, modifiers, and pooling code paths.
- [x] Capture performance baselines (stat query time, modifier update cost) and add profiling hooks.
- [x] Identify legacy behaviors that must remain compatible (e.g., stacking quirks, attribute scaling).
- **Profiling Plan:**
	- Set up micro-benchmarks in a temporary `server/TestStatsProfiler.luau` script that repeatedly calls `Stat:getValue` and modifier update paths (`addModifier`, `removeModifier`, `invalidateAllCaches`).
	- Instrument `StatsManager` and `AttributesManager` with optional `DEBUG_PROFILING` toggles to log execution time for bulk operations (full sync, scaling pass, `invalidateAllCaches`).
	- Capture baseline timings with representative modifier counts (0, 5, 20 per stat) and with pools containing reservations. Record results per stat category (static, pool, attribute).
	- Enable via `StatsManager.setProfilingEnabled(true)` / `AttributesManager.setProfilingEnabled(true)` when gathering timings to capture inline logs.
	- Execute `require(game.ServerScriptService.Server.TestStatsProfiler).run({ iterations = 50000 })` to print micro-benchmark summaries and populate the baseline table below.

### Profiling Baseline – 2025-10-19

| Scenario | Iterations | Total ms | us/op |
| --- | --- | --- | --- |
| PhysicalDamage:getValue (mods=0, recompute) | 50000 | 10.816 | 0.22 |
| PhysicalDamage:getValue (mods=5, recompute) | 50000 | 33.700 | 0.67 |
| PhysicalDamage:getValue (mods=20, recompute) | 50000 | 69.961 | 1.40 |
| PhysicalDamage:getValue (mods=20, cached) | 50000 | 2.116 | 0.04 |
| Stat:add/remove modifier (base=5) | 10000 | 6.316 | 0.63 |
| Stat:add/remove modifier (base=20) | 10000 | 6.456 | 0.65 |
| Stamina add/remove (±5) | 50000 | 8.758 | 0.18 |
| PercentOfStatModifier recompute | 50000 | 11.307 | 0.23 |
| StatsManager.invalidateAllCaches (mods=10) | 250 | 20.422 | 81.69 |
| StatsManager.invalidateAllCaches (mods=40) | 250 | 7.780 | 31.12 |

- Cache hits keep `Stat:getValue` under ~0.05 us/op, while recompute cost scales linearly with modifier count.
- `StatsManager.invalidateAllCaches` stays below 0.1 ms per call even with 40 modifiers, so mediator rollout can target more granular invalidation without a perf crisis.

- **Legacy Compatibility Checklist:**
	- Preserve existing stacking semantics (modifiers applied in insertion order, additive before percent-based only where currently relied upon).
	- Ensure pool reservations continue subtracting from max immediately and clamping current value.
	- Maintain attribute milestone hooks (`AttributesConfig.AttributeMilestones.applyScaling`) and their side-effects on stats.
	- Keep networking payload shapes (`StatsDelta`, `AttributesDelta`) unchanged until dedicated migration step.
	- Respect existing modifier mutability (`modifyValue`, `setActive`) until strategy objects can cover those behaviors.

### Inventory Notes – 2025-10-19
- **StatsManager (server):** registers entities via `StatsConfig.createDefaultStats()`, stores `PlayerStats` table in `entityStats`, pushes deltas through networking channel `StatsDelta`, and exposes helpers for base values, pools, modifiers, and cache invalidation. Each stat instance is expected to provide `setBaseValue`, `getValue`, `addModifier`, `invalidateCache`, etc. Cache invalidation today is coarse (`invalidateAllCaches` iterates every stat).
- **StatClass (shared):** encapsulates base/static stat with `modifiers` array and cached value flags. Modifiers implement `apply(lastValue, allStats)`. No ordering between additive/multiplicative; execution is insertion order. Dirty flag toggled on mutation.
- **PoolStatClass:** extends `StatClass` with `currentValue`, reservation support, and additional caches (`_maxCachedValue`). Reservations subtract flat or percent amounts; operations touch `self.reservations` directly and rely on `_markDirty` to recompute caps.
- **Modifier Implementations:** `StatModifier` carries `{ value, type = "flat"|"percent", condition, source_id }`; `PercentOfStatModifier` references another stat and multiplies by `value`. Modifiers are mutable (e.g., `modifyValue`) and rely on external systems to toggle `isActive`.
- **AttributesManager (server):** mirrors StatsManager for attributes using `AttributesConfig.createDefaultAttributes()`. Handles spend/allocate flows, per-player versioning, and milestones via `AttributesConfig.AttributeMilestones`. Attribute updates trigger `applyAllScaling`, re-running milestone hooks.
- **AttributeClass:** base value + flat modifiers with cached value. Includes helper methods for specific scaling formulas (physical damage, mana, etc.) directly on the attribute object.
- **Networking Touchpoints:** Both managers manually emit deltas (`sendStatDelta`, `sendAttrDelta`) with timestamps/versioning; there is no centralized change event bus yet. Clients rely on `AttributesDelta`/`StatsDelta` payloads for UI updates.
- **Config Entrypoints:** Default data/validation lives in `StatsConfig`/`AttributesConfig` (not yet refactored). Any mediator redesign must either wrap these or produce compatible factories.

## Phase 1 – Mediator & Query Pipeline
- [x] Introduce a dedicated `StatsMediator` with modifier caches keyed by `StatType`.
	- Scaffolded in `src/server/Mediators/StatsMediator.luau` with per-stat buckets and global hit/miss counters.
- [ ] Route all stat queries through mediator `Query` objects; add instrumentation counters.
	- `StatsManager.getStatValue`, pool/resource max helpers, and core combat/skill lookups now issue mediator queries; regeneration + other mutation-heavy services still pending review.
- [ ] Expose mediator events (e.g., `resolveSkillResource`) so observers can override default stat usage without branching inside skills.
- [ ] Implement cache invalidation hooks on modifier add/remove and on timed expiry.
- [ ] Write regression tests ensuring current stat totals match the legacy pipeline.

## Phase 2 – Operation Strategies & Factories
- [ ] Define `IOperationStrategy` variants (add, multiply, percent-of-base, clamp, etc.).
- [ ] Update modifiers to hold `{ type, strategy, metadata }` instead of hardcoded arithmetic.
- [ ] Create factory helpers for common gameplay intents (flat buff, percent buff, attribute-scaling boost).
- [ ] Document stacking order conventions and expose configuration for designer overrides.

## Phase 3 – Timed Modifier Lifecycle
- [ ] Extract a reusable countdown timer utility (pause/resume, events).
- [ ] Ensure modifiers own their timers, mark themselves for removal, and emit `OnDispose`.
- [ ] Harmonize status effects, regen overrides, and buffs to share the same lifecycle hooks.
- [ ] Add unit tests around timer edge cases (pause, resume, simultaneous expiry).

## Phase 4 – Observability & Events
- [ ] Emit `Stats.Changed` events when cached values shift after mediator recompute.
- [ ] Update UI, FX, and analytics consumers to subscribe instead of polling.
- [ ] Extend networking telemetry to include stat-change envelopes for optional replay.
- [ ] Capture before/after metrics to confirm responsiveness improvements.

## Phase 5 – Migration & Cleanup
- [ ] Provide adapter shims for legacy modifier definitions until all content migrates.
- [ ] Remove deprecated paths once parity is verified in playtests.
- [ ] Update documentation, diagrams, and onboarding guides with the new workflow.
- [ ] Lock in automated tests to prevent regressions and track stat pipeline health.

## Open Questions
- How do attribute point allocations flow through the mediator without double-counting modifiers?
- Which modifiers require designer-facing authoring tools, and what metadata do they need?
- Do we need rollback/replay support for stat changes in PvP scenarios?

## Next Checkpoint
Schedule a spike to prototype Phase 1 mediator caching, measure the impact, and validate compatibility with existing combat calculations.
