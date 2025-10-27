# Stats System Overview

The stats layer runs server-side and replicates deltas to clients via the networking dispatcher. Core files live under `src/server/Stats/` and `src/shared/`.

## Key Modules

- `StatsManager.luau`: authoritative store for per-entity stats and pools. Handles registration, replication (`StatsDelta` events), regeneration ticks, and modifier application.
- `StatsMediator.luau`: query layer with caching, observer hooks, and instrumentation. Skills use it to preview costs, tempo, or custom calculations without duplicating cache logic.
- `Config/StatsConfig.luau`: builds default stats, pools, and resources (`PoolStatClass`, `StatClass`, `ResourceStatClass`).
- `AttributesManager.luau`: interacts with attributes and modifiers, feeding back into StatsManager.
- Shared classes in `src/shared/`: `StatClass`, `PoolStatClass`, `ResourceStatClass`, `Modifiers/*`, and `StatTypeUtil.luau` provide the common behaviour for stat arithmetic and serialization.

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
