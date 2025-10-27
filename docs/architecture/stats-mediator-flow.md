# Stats Mediator Flow

This guide documents the server-side stat mediation pipeline that allows systems to layer caching, observers, and metadata-driven overrides on top of raw stat and pool accessors.

## High-Level Goal

The mediator creates a single touch-point for stat queries. Callers (skills, combat, regeneration, etc.) provide contextual metadata; observers inspect or modify the request; the mediator handles caching, instrumentation, and cache invalidation.

```
Caller → StatsManager → StatsMediator → Observers → Concrete Stat/Pool Instance
```

## Core Participants

- **Caller helpers** – e.g. `BaseSkill:queryPoolCurrent`, `BaseSkill:applyResourceCost` craft query options and metadata.
- **StatsManager** – merges defaults, forwards all reads (and some writes) through the mediator.
- **StatsMediator** – owns per-entity caches, observer registry, instrumentation.
- **Observers** – optional modules that subscribe via `StatsMediator.observe(eventName, callback)` to modify behaviour.
- **Concrete stat/pool** – performs the actual computation (e.g. `PoolStat:removeFromCurrentValue`).

## Standard Query Flow

1. **Caller builds options**
   ```lua
   local options = self:_buildSkillQueryOptions("resolveSkillCost", metadata, overrides)
   StatsManager.removeFromPool(self.caster, poolType, baseCost, options)
   ```
   - Metadata is merged with skill identity, tags, caster references.
   - Callers can opt-in/out of caching or override the event name when needed.

2. **StatsManager.mergeQueryOptions**
   ```lua
   local resolved = mergeQueryOptions("removeFromPool", "removed", options)
   resolved.cacheEnabled = false
   ```
   - Ensures each lookup has consistent `context`, fallback `cacheKey`, and default `event` (falls back to the context when omitted).
   - Mutations (like cost spends) commonly disable caching.

3. **StatsMediator.resolve**
   - Wraps the call in a `Query` object, tracks diagnostics.
   - Checks cache buckets (skipped when `cacheEnabled == false`).
   - Determines the event name (`options.event` or `options.context`).

4. **Observer emission**
   ```lua
   local observerResult = emit(eventName, {
       event = eventName,
       entity = entity,
       statType = statType,
       options = options,
       compute = computeWithInstrumentation,
   })
   ```
   - Calling `StatsMediator.observe("resolveSkillCost", callback)` registers callbacks; each observer receives the shared `options` table.
   - Observers can mutate `options.metadata` (e.g. stacking cost reductions) or call `context.compute()` to evaluate the base value.
   - Returning `nil` (or `{ handled = false }`) lets subsequent observers run; returning `{ handled = true, value = ... }` short-circuits the chain.

5. **Resolver execution**
   ```lua
   local removed = StatsMediator.resolve(entity, poolName, function()
       local meta = resolvedOptions.metadata
       local finalAmount = meta and meta.adjustedCost or amount
       if meta then meta.finalCost = finalAmount end
       return pool:removeFromCurrentValue(finalAmount)
   end, resolvedOptions)
   ```
   - The closure reads whatever observers wrote into `metadata` and performs the actual stat/pool operation.
   - The return value is forwarded back to the caller (and used for post-update deltas).

6. **Invalidation & Deltas**
   - Mutating methods trigger cache invalidations (`StatsMediator.invalidateStat`) and send deltas to clients via `StatsManager`.
   - Read paths simply return the computed or cached value.

## Observer Patterns

### Stacking Modifiers
```lua
local token = StatsMediator.observe("resolveSkillCost", function(ctx)
    local meta = ctx.options and ctx.options.metadata
    if not meta then return end

    local base = meta.adjustedCost or meta.baseCost or ctx.compute()
    meta.adjustedCost = math.max(0, base * 0.9)
    return nil -- keep pipeline running
end)
```
- Each observer edits the same `meta` table; later observers see prior adjustments.
- The final resolver reads `meta.adjustedCost` and applies the cumulative result.

### Short-Circuit / Override
```lua
StatsMediator.observe("resolveSkillCost", function(ctx)
    if not playerHasBuff(ctx.entity) then
        return
    end
    local meta = ctx.options and ctx.options.metadata
    if meta then meta.finalCost = 0 end
    return {
        handled = true,
        value = true,
        storeInCache = false,
    }
end)
```
- Returning `handled = true` stops execution before the resolver runs (the pool is untouched).
- The chosen `value` is handed back to the original caller.

### Instrumentation
- Set `options.instrument = true` to capture per-query runtime (stored in the cache entries when caching is enabled).
- `StatsMediator.getDebugSnapshot(entity?)` exposes hit/miss counts and cached entries for debugging.

## Implementation Checklist for New Callers

1. Build metadata describing intent (skill name, category, target stat/pool, any extra context).
2. Call the appropriate `StatsManager` helper with that metadata.
3. If you expect observers to modify the final value, disable caching (or choose distinct `cacheKey` values per variant).
4. For write operations (pool spends, modifier updates), ensure post-operation deltas are still emitted.
5. Optionally document or register observers in a dedicated module so features (e.g. perks, buffs) hook into consistent event names.

## Event Naming Guidance

- Use specific strings for distinct hooks: e.g. `resolveSkillResource`, `resolveSkillCost`, `skillDamageQuery`, `combatMitigationQuery`.
- By default, `mergeQueryOptions` falls back to the logical `context` when no event is supplied, so legacy callers still emit usable events.
- Keep observer registration close to the feature that owns the modifier for discoverability.

## Troubleshooting

- **Value never changes**: ensure caching is disabled or the cache key differs when mutating metadata, otherwise stale entries persist.
- **Observer not firing**: double-check event string matches (`observe("resolveSkillCost")` vs. `options.event`).
- **Order sensitivity**: if ordering matters, structure observers accordingly or merge them into a single module that manages priority.
- **Final metadata missing**: remember to seed fields such as `baseCost` so observers have an initial reference.

With this structure, any system can reason about stat queries: metadata establishes intent, observers inject custom rules, and StatsManager remains the single authoritative surface for stat mutations and reads.
