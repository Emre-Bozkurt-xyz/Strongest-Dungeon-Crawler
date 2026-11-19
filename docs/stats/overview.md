# Stats System Overview

The stats layer runs server-side and replicates deltas to clients via the networking dispatcher. Core files live under `src/server/Stats/` and `src/shared/`.

## Key Modules

- `StatsManager.luau`: authoritative store for per-entity stats and pools. Handles registration, replication (`StatsDelta` events), regeneration ticks, and modifier application.
- `StatsMediator.luau`: query layer with caching, observer hooks, and instrumentation. Skills use it to preview costs, tempo, or custom calculations without duplicating cache logic.
- `Config/StatsConfig.luau`: the game's stat defaults; builds every entity's stats, pools, and resources (`PoolStatClass`, `StatClass`, `ResourceStatClass`).
- `AttributesManager.luau`: interacts with attributes and modifiers, feeding back into StatsManager.
- Shared classes in `src/shared/`: `StatClass`, `PoolStatClass`, `ResourceStatClass`, `Modifiers/*`, and `StatTypeUtil.luau` provide the common behaviour for stat arithmetic and serialization.

## Base Values

Base stats are derived, never saved. Every entity gets `StatsConfig.createDefaultStats()` when it registers (`StatsManager.register`: a player at session start, an NPC when it spawns), so a default changed in `StatsConfig.luau` reaches everyone at their next session. Anything a player keeps is saved as its inputs (level, attribute points, items), which come back as modifiers; never save a stat value.

A stat's base has two layers (`StatClass`):

- **Default** (`getDefaultValue`): what the stat inherits from `StatsConfig`, unless the entity's definition sets its own. A definition writes it with `stat:setBaseValue(value)` in the `configure` option of `StatsManager.register` (NPC specs' `damageable.configure`) or while building the entity (the NPC Combat component's `damage`); from then on the stat `ownsDefaultValue()` and no longer follows the game default.
- **Override** (optional): a session-level replacement, for dev tooling and tests. `StatsManager.setBaseOverride(entityId, stat, value)` (clamped to the stat's limits), `clearBaseOverride(entityId, stat)`, `getBaseOverrides(entityId)`. Clearing returns the stat to its default as it is then.

The effective base (`stat.baseValue`, `getBaseValue()`) is the override, else the default; modifiers, pool maximums, mediator queries and the client mirror read only that. `StatsManager.getBaseInfo(entityId, stat)` returns `{ default, override?, base, ownsDefault }`. A change of the effective base invalidates every cached stat of the entity (other stats can be computed from it), keeps a pool's current value within its new maximum without refilling it, and sends the player `base_value_changed` (and `current_value_changed` when the pool's current value was clamped). There is no plain "set base" on `StatsManager`: a write that does not say which layer it is would silently undo a rebalance of the default.

`StatsManager.applyGameDefault(stat, value)` moves every registered entity that still inherits a default onto a new value; dev tooling uses it with `StatsConfig.setSessionDefault` to retune defaults live (`docs/dev-tooling/overview.md`, Game defaults).

## Querying Stats Safely

When you need a stat value inside gameplay code:

```lua
local StatsManager = require(Server.Stats.StatsManager)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)

local attackSpeed = StatsManager.getStatValue(entity, StatTypes.StaticStats.AttackSpeed, {
	context = "resolveSkillTempo",
	allowObservers = true,
})
```

Always supply a context so `StatsMediator` observers can react. For pooled resources (`Health`, `Mana`, `Stamina`), use `getPoolCurrentValue` / `getPoolMaxValue` or `resolvePoolCost` when previewing spends.

## Resource Cost Pipeline

1. `BaseSkill:applyResourceCost` calls `previewResourceCost`, which delegates to `StatsManager.resolvePoolCost`.
2. Observers listening to `resolveSkillCost` can redirect costs to alternate pools, adjust amounts, or inject metadata for telemetry.
3. After preview, `StatsManager.removeFromPool` applies the final cost and emits deltas to clients.

If a resource cost fails (for example insufficient stamina), the skill should abort and allow the player to retry once the pool recovers.

## Replication to Clients

`StatsManager` serializes deltas through the `Stats` channel. Clients subscribe in `src/client/StatsClient.luau`, maintain a local copy, and provide `onChanged` signals for UI.

Block by block replication keeps payloads minimal. If a client misses initial data (e.g. due to ordering), it can call `StatsClient.requestStatsUpdate()` to fetch a full snapshot via `StatsRequest`.
