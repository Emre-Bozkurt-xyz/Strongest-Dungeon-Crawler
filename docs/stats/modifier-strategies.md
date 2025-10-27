# Modifier Strategy Pipeline

This document captures the Phase 2 strategy / factory work for character modifiers.

## Strategy Interface

* `Strategies.StrategyContext` supplies `lastValue`, `baseValue`, `stat`, `stats`, `modifier`.
* Strategies are pure tables `{ kind, apply(context) }`; available kinds:
  * `operation:add` – additive delta, uses `payload.magnitude` / `value`.
  * `operation:percent_of_base` – adds `baseValue * magnitude` before other scaling.
  * `operation:percent_of_stat` – adds `otherStat * magnitude` using `payload.targetStat` or override.
  * `operation:multiply` – multiplies by `payload.multiplier` (defaults to `1 + magnitude`).
  * `operation:clamp` – clamps to `payload.min`/`payload.max` after other operations.

## Modifier Shape

* Each modifier is declarative: `{ source_id, strategyKind, payload, tags?, stackGroup?, priority?, metadata?, duration? }`.
* `StatModifier` enforces strategies—legacy `type = "flat" | "percent"` is mapped to `operation:add` or `operation:multiply` automatically.
* Payload values stay in sync when a modifier is updated (`payload.magnitude`, `payload.coefficient`, etc.).

## Factory Helpers (`Shared.Modifiers.Factories`)

```
ModifierFactories.flatAdd({ sourceId, amount, description?, tags?, stackGroup?, priority?, metadata? })
ModifierFactories.percentBuff({ sourceId, percent, ... })
ModifierFactories.percentOfBase({ sourceId, percent, ... })
ModifierFactories.percentOfStat({ sourceId, targetStat, percent, ... })
ModifierFactories.clamp({ sourceId, min?, max?, ... })
ModifierFactories.hydrate(serializedModifier) -- rebuilds a modifier from serialized metadata
```

Factories always emit fully-populated modifier instances with:
* strategy reference + params
* cloned payload metadata
* default priorities (`add=100`, `percent_of_base=200`, `percent_of_stat=220`, `multiply=300`, `clamp=1000`)
* optional tags and stack groups for traceability.

## Stacking Order & Adapters

* `Stat:addModifier` now sorts by `priority`, then insertion order.
* Default order: additive → percent-of-base → percent-of-stat → multiplicative → clamp.
* Legacy constructors remain: `StatModifier.new({ type = "flat" })` auto-resolves to `operation:add` so existing content still works.
* Adapter path: move call sites to `ModifierFactories.*`; if an existing system must stay raw, supply `strategyKind = Strategies.KINDS.Add` (etc.) explicitly during migration.

## Validation Plan

Before flipping defaults globally:
1. Snapshot representative stacks (equipment, buffs, attribute scaling) under the legacy branch.
2. Rebuild the same stacks using factories and compare outputs:
   * additive-only chains (flat stacking)
   * mixed additive + multiplicative chains
   * percent-of-base + clamp interactions
   * percent-of-stat pulling from pools/resources
3. Exercise `StatsTypeUtil.serialize/deserialize` to ensure round-trips preserve `strategyKind`, `payload`, tags, and ordering.
4. Verify `StatsManager.updateModifier` updates magnitude + payload for each strategy type.

Automation hooks can live in `TestStatsProfiler` once we add dedicated comparison fixtures.
