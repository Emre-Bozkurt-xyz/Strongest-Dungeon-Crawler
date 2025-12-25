# Skills & FX System Evolution Plan

This document outlines a step‑by‑step plan to evolve the current skills, FX, and stats systems toward a predictable, composable, and latency‑tolerant architecture.

The goal is to keep the good parts you already have (server authority, data‑driven configs, entityId‑first), while making the flow easier to trace and extend.

---

## 0. High‑level objectives

- **Responsive but authoritative skills**
  - Client predicts whether a skill can be used and starts animations/FX immediately.
  - Server remains the single source of truth for hits, damage, resources, and cooldowns.

- **Traceable skill attempts**
  - Both client and server treat each skill use as a clear state machine (attempt lifecycle), so it is easy to debug where things went wrong.

- **Unified, explicit FX lifecycle**
  - Exactly one authoritative path for shared FX (things others must see and that must stop), and a clear contract for start/stop.
  - Marker‑driven FX integrate cleanly with that path.

- **Composable skills & FX**
  - Fewer deep inheritance trees, more composable components (e.g. timing, cost, FX, projectiles) plugged into a skill definition.

- **Robust stat/metadata cache**
  - Server keeps the real stats and derived values.
  - Client has a well‑defined, readonly mirror used for prediction, with a clean query API inspired by caching/back‑end systems.

The rest of this doc is organized into phases you can tackle incrementally.

---

## Known issues (current state)

These are regressions or oddities observed after the initial client–server skill model migration. They are intentionally kept here as a backlog to revisit once the core model is clean and transparent.

- Skill damage from server-driven skills is not being applied reliably (either hitboxes are not registering targets correctly, or `CombatService` damage application is not being invoked/propagated).
- Custom NPC overhead health bars no longer appear, despite previously working before the migration (likely tied to `EntityInfoService`, presence events, or their UI consumers).
- ~~Some FX behave incorrectly: duplicated playback, looped FX not stopping, and possible echo/feedback issues when replicated FX are sent back to clients (FX replication path and `FXPlayer`/replicator lifecycle need a full pass).~~ **FIXED** - FX now properly replicate via server relay with echo-back prevention and step-aware keying.
- pool stats dont seem to be regenerating (i can see this in the client when resource bars go down on skill usage, but they dont regenerate as they used to before (look at regeneration service)) 

These should not be tackled piecemeal; the plan below aims to rebuild the skills/stat/FX pipeline in a way that makes these easier to diagnose and fix systematically.

---

## 1. Make "SkillAttempt" a first‑class concept

### 1.1 Define a shared lifecycle

Introduce a conceptual (or explicit) type for a **SkillAttempt** with these phases:

- `idle` – no attempt in progress.
- `local_predicted` – client accepted input locally and started visuals.
- `pending_server` – request sent to server, response not yet received.
- `server_confirmed` – server accepted and execution is in progress.
- `rejected` – server or client rejected use; attempt should roll back/cleanup.
- `completed` – execution finished on the server (including recovery), cooldown has started.

On the **server**:

- `SkillsManager.canUse` + `ActionPermissions` + `CooldownService` decide whether a new attempt is allowed (SessionManager enforces the active session lock).
- `SessionManager` and its session state represent the in-progress attempt.
- `SessionManager.transition(..., "COMPLETED"/"CANCELLED")` is the authoritative transition to `completed`.

On the **client**:

- `BasicComboSkill:use` (
  or any skill client wrapper) performs `canUseLocally` and moves into `local_predicted`.
- A single call to `SkillsClient` → dispatcher request is the transition to `pending_server`.
- Server response → `server_confirmed` or `rejected`.

### 1.2 Codify this in code

1. Add a small shared module (e.g. `shared/skills/AttemptState.luau`) that:
   - Defines allowed phases.
   - Exposes helpers like `canTransition(from, to)` for consistency and logging.

2. On the **client**:
   - In `SkillsClient` or per‑skill client classes, maintain a tiny attempt record per (skill, entityId):
     - `{ id, skillName, state, lastUpdate, metadata }`.
   - Use this to drive:
     - When to start animations/FX.
     - When to reconcile on server response.
     - When to stop long‑lived FX (`completed`/`rejected`).

3. On the **server**:
   - Attach a logical "attempt id" to the SkillRequestUse payload/response and keep it in AttemptStore metadata.
   - SkillSession events carry `sessionId`; include `attemptId` in FX metadata so cleanup can correlate.

**Why:** This gives a single, named thing to trace when debugging combos, costs, FX, and desyncs.

---

## 2. Harden the client stats / skill metadata mirror

### 2.1 Introduce a dedicated client stats/metadata store

Create a client‑side module (e.g. `client/Stats/StatsClient.luau` or `ClientStatsStore`) that:

- Holds readonly, client‑side mirrors of:
  - Base stats and derived stats (as much as the server chooses to replicate).
  - Pool values (HP/Mana/etc.).
  - Per‑skill metadata (costs, tags, base durations, categories, etc.).

- Subscribes to server updates:
  - `StatsDelta` events (already used by `StatsManager`)
  - Skill metadata events from `SkillsMetadataService`.

- Exposes a small query API used by the client skills layer, for example:
  - `canAfford(skillName, step?)`.
  - `getPoolCurrent(entityId, poolType)`.
  - `getPredictedTempo(entityId, skillName)`.
  - `getSkillMetadata(skillName)`.

The **goal** is that `BasicComboSkill`, `BasicSkill`, `SkillsClient`, etc. **never** need to know the details of incoming deltas or raw network payloads. They only talk to this store.

### 2.2 Align with server query semantics

On the server, `StatsMediator` + `StatsManager` already support queries like:

- `resolveSkillTempo(entityId, skillName, metadata)`.
- `resolveSkillCost(entityId, poolType, amount, metadata)`.

Plan to mirror **the shape** of these queries on the client store, even if the math is simplified client‑side:

- Same function names / signatures where possible.
- Same `metadata` shape (event names, skill tags, etc.).

The client implementation can:

- Use the last known stats/pools.
- Use cached per‑skill summaries from `SkillsMetadataService`.
- Return best‑effort predictions that are _usually_ correct.

If the server later disagrees, the attempt state machine (Section 1) handles correction.

---

## 3. Unify and bulletproof the FX lifecycle

### 3.1 Decide FX ownership per type

Define two categories of FX:

1. **Shared / authoritative FX**
   - Must be seen by other players and remain in sync.
   - Examples: projectile trails, AOE circles, big impacts, persistent auras.
   - **Rule:** Always go through the `FX` dispatcher channel via `FXReplicator.server` and `client/fx/Replicator`.

2. **Local, cosmetic FX**
   - Only matter for the local player.
   - Examples: tiny hit flashes, screen shakes, subtle camera‑only dust.
   - **Rule:** Can be driven purely client‑side via animation markers and `FXPlayer` without a network hop.

Document this split in this file and near the `FXReplicator` modules.

### 3.2 Normalize shared FX to one path

For **shared FX**:

1. Ensure all triggers (server skills, animation markers, projectiles) call into a single place, for example:
   - `FXReplicator.emitFX` on the client for client‑driven events.
   - A helper on the server (`Services.FXReplicator.emitToRange` or similar) for server‑driven FX.

2. Avoid directly calling `FXPlayer` for anything that needs to be seen by others. Instead:
   - For animation markers, route them through `FXReplicator.emitFX`.
   - For server‑side skill logic, emit `FXEvent` payloads using the same schema (`fxKey`, `entityId`, `anchorName`, `action`, etc.).

Result: there is one code path that decides how a shared FX is attached, which clients see it, and how it is stopped.

### 3.3 Strengthen the FX handle contract

1. **FX handle structure**
   - Standardize on an `FXHandle` interface:
     - `{ Instance: Instance, Stop: () -> () }` (already present in `FXPlayer`).
   - `fx.Replicator` should store:
     - `fxMap[entityId][fxKey] = { handle = FXHandle, meta = { skill = skillName, attemptId = ..., ... } }`.

2. **Start/stop rules**
   - Any payload with `action = "start"` must be paired with a corresponding `action = "stop"` when:
     - A given skill attempt completes or is canceled.
     - The entity dies or is removed.
   - Enforce this at the skills layer (see Section 4) so that even if a marker forgets to send `stop`, a catch‑all cleanup happens.

3. **Small robustness fixes**

   - In `FXPlayer.spawnAt`, use a short linger instead of `+ 100` seconds:
     - `Debris:AddItem(fx, linger + 0.1)`.
   - In `client/fx/Replicator`:
     - Do not early‑return when `entityId` is nil; instead, treat it as a world/"Server" FX and let it fall through.
     - Let `findAnchor` handle `nil` entities gracefully and fall back to world‑space FX when no anchor can be found.

---

## 4. Integrate FX with skill & attempt lifecycle

### 4.1 Centralize FX hooks per skill attempt

Tie FX to the `SkillAttempt` phases defined in Section 1:

- **On `local_predicted`** (client):
  - Start local animation and any _local‑only_ FX immediately (e.g. a quick anticipation FX).
  - Optionally kick off shared FX via `FXReplicator.emitFX` if you want them to feel instant.

- **On `server_confirmed`**:
  - Reconcile timing (durationScale, window, step) from server metadata.
  - Adjust or restart FX that depend on precise timings if needed.

- **On `rejected`**:
  - Stop any shared FX that were started for this attempt.
  - Optionally fade out local‑only FX.

- **On `completed`** (server → client event):
  - Stop all long‑lived FX for this (skill, entityId, attemptId).
  - Optionally emit a dedicated `fx` phase or a `skill_end` event that the FX system can listen to.

Implementation direction:

1. Use `SkillSession` events as the authoritative lifecycle signal, and keep `attemptId` in
   SkillRequestUse payload/response plus FX metadata (Replicator meta) for correlation.

2. In `SkillsClient`, listen to SessionMirror terminal events and stop FX via `Replicator`
   while letting per-skill client logic handle local-only FX.

3. Server helpers can add optional FX metadata, but the default cleanup path should be
   "session ended" -> client stops FX/animations deterministically.

---

## 5. Move toward composition over inheritance for skills

The current `BaseSkill` / `BaseComboSkill` split is solid, but you can gradually migrate toward a more composable model.

### 5.1 Identify common components

Some examples of components that can be composed into a skill definition:

- **Timing component** – consults `SkillTimingService` and applies tempo/durationScale.
- **Resource cost component** – uses `StatsManager`/`StatsMediator` to compute costs, preview, and apply.
- **Combo component** – wraps `SessionManager.advanceCombo` and `SessionManager.extendComboWindow`.
- **Hitbox component** – uses `HitboxService` to schedule hit queries at specific times/yaws.
- **Projectile component** – spawns and controls projectiles via `ProjectileService`.
- **FX component** – knows which FX keys to emit for phases/markers.

### 5.2 Represent skill behavior as data + components

Long‑term direction:

1. Keep `SkillsData` / `SkillsConfig` as the source of declarative definitions.
2. Instead of (or in addition to) subclassing `BaseSkill` per skill, define which components a skill uses in its config, for example:

   ```lua
   SkillsConfig.skills.Punch = {
       name = "Punch",
       class = "Skill", -- generic component‑driven skill
       components = {
           Timing = { category = "melee_light" },
           ResourceCost = { baseResource = "Stamina", costs = { 5, 7, 9 } },
           Combo = { steps = 3, window = 0.6, hitDelays = {...}, stepDurations = {...} },
           Hitbox = { pattern = "cone", range = 7, angle = 40 },
           FX = { specKey = "Punch" },
       },
   }
   ```

3. A generic `ComponentSkill` implementation coordinates these components in a standard order:
   - Check can use (cost & cooldown & execution lock).
   - Start execution & combo.
   - Schedule hits.
   - Emit FX / events.

You do not need to do this all at once; you can start by extracting and reusing small components from `BaseSkill`/`BaseComboSkill` as the first step.

---

## 6. Evolve stat queries toward a unified resolver API

### 6.1 Design a message‑like query shape

Take inspiration from back‑end caching / DB systems by treating stat resolution as queries over a stable API.

For example, define a single entry point like:

- `StatsMediator.resolve(context: StatQueryContext): StatQueryResult`

Where `StatQueryContext` might include:

- `entityId: string`
- `skillName: string?`
- `event: string` – e.g. `"resolveSkillTempo"`, `"resolveSkillCost"`, `"resolveSkillResourceMax"`.
- `stat: StatType?` – when relevant.
- `pool: PoolType?`
- `amount: number?` – for cost queries.
- `metadata: { [string]: any }?` – tags, combo step, timing info, etc.

`StatQueryResult` could be a tagged union or table with fields like:

- `value` – main numeric result (e.g. tempo, cost, max value).
- `derived` – optional derived values (current, max, finalCost, poolName, etc.).
- `debug` – optional debug info (which modifiers contributed, cache hits, etc.).

Then:

- Server `StatsMediator` implements the full, precise resolution using all modifiers.
- Client `ClientStatsStore` implements a **subset** of the same interface using mirrored data.

This alignment makes it much easier to:

- Share high‑level logic between client & server.
- Integrate new stat‑based behaviors (e.g. status effects that modify skill tempo) without touching every caller.

### 6.2 Cache behavior inspiration

From caching/back‑end systems, a few patterns worth borrowing:

- **Versioning:**
  - Attach a `version` or `stamp` to stat snapshots and to query results so the client can tell if its cached answer is stale.

- **Idempotent queries:**
  - Make stat queries side‑effect free; separate "preview" from "apply" distinctly.
  - You are already doing this separation between preview (`resolvePoolCost`) and apply (`removeFromPool`).

- **Central invalidation:**
  - Keep all cache invalidation logic in `StatsMediator`/`StatsManager` on the server, and have the client mirror follow that through deltas instead of each subsystem trying to invalidate on its own.

These do not require a rewrite, but they are good guiding principles as you extend the system.

### 6.3 Attack Composition System

One of the key applications of the unified resolver is **attack composition** - representing damage application as a collection of composable packets that can be modified by the resolver pipeline.

#### 6.3.1 Core Concept

An **attack** is not a single damage value, but a collection of **packets** (damage instances, status effect applications, heals, drains, etc.) that get applied together. This enables:

- **Multi-type damage**: 80% Fire + 20% Physical from a single hit
- **Effect application**: Fire damage has a chance to apply Burn
- **Complex interactions**: Modifiers can convert damage types, add/remove packets, scale values

#### 6.3.2 Type Definitions

Define in `shared/skills/AttackTypes.luau`:

```lua
export type AttackPacket = {
    type: "damage" | "effect" | "heal" | "drain" | "knockback",
    
    -- Damage packets
    damageType: string?,     -- "Physical", "Fire", "Lightning", etc.
    amount: number?,
    penetration: number?,    -- armor penetration 0.0-1.0
    
    -- Effect packets
    effectId: string?,       -- "Burn", "Wound", "Stun"
    chance: number?,         -- 0.0 to 1.0 (nil = 100%)
    params: any?,            -- effect-specific params (power, duration, etc.)
    
    -- Heal/Drain packets
    poolType: string?,       -- "HP", "Mana"
    
    -- Knockback packets
    force: number?,
    direction: Vector3?,
}

export type AttackContext = {
    packets: { AttackPacket },
    sourceId: string,
    metadata: {
        skillId: string?,
        tags: { string }?,
        isCrit: boolean?,
        comboStep: number?,
        [string]: any,
    }
}
```

#### 6.3.3 Integration with Query Resolver

Add a new query event `"resolveAttack"` that skills use to build attacks:

```lua
-- In BaseSkill (server)
function BaseSkill:resolveAttack(base: {
    damage: number,
    damageType: string,
    [string]: any
}): AttackContext
    local ctx = self:_buildQueryContext("resolveAttack", base, {
        isCrit = self:rollCrit(),
        comboStep = -- current step if combo
    })
    
    local result = SkillMediator.resolve(ctx)
    
    return {
        packets = result.packets or {
            {type = "damage", damageType = base.damageType, amount = base.damage}
        },
        sourceId = self.casterId,
        metadata = {
            skillId = self.name,
            tags = self.config.tags,
            isCrit = ctx.metadata.isCrit,
        }
    }
end
```

Skills call this once per hit, then pass the result to CombatService:

```lua
function SwordSlash:onHit(targetId)
    local attack = self:resolveAttack({
        damage = 1000,
        damageType = "Physical",
    })
    CombatService.applyAttack(targetId, attack, self.casterId)
end
```

#### 6.3.4 Modifier Examples

**Fire Conversion** (from passive/enchant):
```lua
{
    id = "FlameEnchant",
    priority = 100,
    matches = function(ctx)
        return ctx.base.damageType == "Physical"
    end,
    apply = function(ctx, result)
        local total = ctx.base.damage
        result.packets = {
            {type = "damage", damageType = "Fire", amount = total * 0.8},
            {type = "damage", damageType = "Physical", amount = total * 0.2}
        }
    end
}
```

**Burn Application** (from Fire damage):
```lua
{
    id = "IgniteChance",
    priority = 200,
    matches = function(ctx)
        for _, p in (result.packets or {}) do
            if p.type == "damage" and p.damageType == "Fire" then
                return true
            end
        end
        return false
    end,
    apply = function(ctx, result)
        table.insert(result.packets, {
            type = "effect",
            effectId = "Burn",
            chance = 0.3,
            params = {power = 50, duration = 5}
        })
    end
}
```

**Wound from Slash** (from skill tag):
```lua
{
    id = "SlashWound",
    priority = 200,
    matches = function(ctx)
        return ctx.tags and table.find(ctx.tags, "slash")
    end,
    apply = function(ctx, result)
        table.insert(result.packets, {
            type = "effect",
            effectId = "Wound",
            chance = 0.15,
            params = {severity = 2, duration = 8}
        })
    end
}
```

**Crit Multiplier**:
```lua
{
    id = "CritDamage",
    priority = 50,
    matches = function(ctx) return ctx.metadata.isCrit end,
    apply = function(ctx, result)
        for _, p in result.packets do
            if p.type == "damage" then
                p.amount = p.amount * 2.0
            end
        end
    end
}
```

#### 6.3.5 CombatService Packet Processor

Update `CombatService.applyAttack()` to process packets:

```lua
function CombatService.applyAttack(targetId: string, attack: AttackContext, sourceId: string)
    for _, packet in attack.packets do
        if packet.type == "damage" then
            -- Apply damage with type-specific logic (resistances, armor, etc.)
            CombatService._applyDamagePacket(targetId, packet, sourceId, attack.metadata)
            
        elseif packet.type == "effect" then
            -- Roll chance and apply status effect
            local shouldApply = not packet.chance or math.random() <= packet.chance
            if shouldApply then
                StatusEffectsService.apply(targetId, packet.effectId, sourceId, packet.params)
            end
            
        elseif packet.type == "heal" then
            local poolType = packet.poolType or "HP"
            StatsManager.addToPool(targetId, poolType, packet.amount)
            
        elseif packet.type == "drain" then
            local poolType = packet.poolType or "HP"
            StatsManager.removeFromPool(targetId, poolType, packet.amount)
            StatsManager.addToPool(sourceId, poolType, packet.amount)
            
        -- Future: knockback, displacement, etc.
        end
    end
end
```

#### 6.3.6 Benefits

- ✅ **Compositional** - Attacks are flexible collections of packets
- ✅ **Extensible** - Easy to add new packet types without changing skills
- ✅ **Modular** - Damage conversion, effect application, scaling are separate concerns
- ✅ **Streamlined** - Skills: one call to `resolveAttack()` → `applyAttack()`
- ✅ **Integrates naturally** - Works with StatusEffectsService out of the box
- ✅ **Query Resolver Native** - All transformations happen via modifiers
- ✅ **Type-Safe** - AttackPacket is a discriminated union

#### 6.3.7 Implementation Order

1. **Define types** - Create `shared/skills/AttackTypes.luau` with packet types
2. **Update CombatService** - Add `applyAttack()` packet processor alongside existing `applyDamage()`
3. **Add `resolveAttack` event support** - Wire into SkillMediator resolver
4. **Create `BaseSkill:resolveAttack()` helper** - Convenience wrapper that builds context
5. **Migrate one skill** - Prove the pattern (e.g., Punch or a simple melee skill)
6. **Add sample modifiers** - Fire conversion, burn application, crit multiplier
7. **Gradually migrate other skills** - Replace direct `applyDamage()` calls with attack composition
8. **Deprecate old damage path** - Once all skills use attack composition, remove legacy `applyDamage()` overloads

---

## 7. Tracking progress

As you work through this plan, you can keep a simple checklist here and update it over time.

```markdown
- [x] 1.1 – SkillAttempt lifecycle states defined (AttemptState.luau)
- [x] 1.2a – Client attempt tracking implemented (AttemptStore.luau)
- [x] 1.2b – attemptId propagation client→server→response
- [x] 1.2c – FX cleanup wired to attempt lifecycle (stopAllForAttempt on complete/reject)
- [x] 1.2d – FX metadata storage includes attemptId for precise cleanup
- [x] 1.2e – Server emits completion events with attemptId (for client reconciliation)
- [x] 2.1 – Client stats/metadata store created (ClientStatsStore.luau)
- [x] 2.2 – BasicComboSkill migrated to use ClientStatsStore.canAfford
- [x] 3.1 – FX ownership categories documented (shared vs local)
- [x] 3.2 – Shared FX normalized via FXReplicator with server relay
- [x] 3.3a – Step-aware FX keying prevents combo interference
- [x] 3.3b – Echo-back prevention via exclude parameter
- [x] 3.3c – Client filtering to prevent local duplication
- [x] 3.3d – FXPlayer.spawnAt linger fix (use linger + 0.1 not + 100)
- [x] 3.3e – Replicator FX handle storage with metadata (attemptId, skillName)
- [x] 3.3f – Cleanup helpers (stopAllForSkill, stopAllForAttempt, stopAllForEntity)
- [x] 4.1 – Listen to attempt lifecycle in SkillsClient for event coordination
- [ ] 5.x – First skill migrated to a more composable component‑style definition
- [ ] 6.x – Unified stat resolver API sketched and piloted on one or two query types

**Known Issues Backlog:**
- [x] Regeneration – **FIXED** - getAllEntities iteration bug (used pairs instead of ipairs)
- [x] Health Bars – **FIXED** - applyReveal called with wrong parameter (Model instead of entityId)
- [x] Damage – **FIXED** - User fixed hitbox registration / CombatService invocation
- [x] GCD Prediction – **FIXED** - Client was checking "__gcd" instead of "_GCD", causing false-positive predictions
- [ ] Debug verification – Test regen and health bars in-game with new logging
```

You can expand this list with finer‑grained items as you go (e.g. per‑skill or per‑component tasks).

---

## 8. Concrete migration steps (server + client)

This section breaks the high‑level goals into concrete, ordered steps that you can follow. Each step is intended to be shippable on its own.

### 8.0 Attack Composition System (PRIORITY: Implement BEFORE 8.1) ✅ **COMPLETED**

This provides the foundation for how damage and effects are applied through the resolver.

**Step 1: Define Attack Types** ✅

Created `src/shared/skills/AttackTypes.luau` with complete type system for packet-based attacks.

**Step 2: Update CombatService** ✅

Added `applyAttack()` method and `applyDamagePacket()` helper to process packet collections. Handles damage, effect, heal, and drain packet types. Maintains backward compatibility with existing `applyDamage()`.

**Step 3: Wire into Query Resolver (preparation for 8.1-8.2)** ✅

Created `SkillMediator` with `resolve()` function supporting "resolveAttack" query type. Updated `BaseSkill:resolveAttack()` to use resolver pipeline (currently returns simple packets, will support modifiers once registry implemented).

**Step 4: Migrate One Skill** ✅

Migrated Punch skill to use attack composition. Changed from `CombatService.applyDamage()` to `CombatService.applyAttack()` with `self:resolveAttack()` call.

**Step 5: Test & Validate** ✅

In-game testing complete. Damage application works correctly, values match old system. Ready for modifier additions.

**Step 6: Add Modifiers (after 8.3 - Modifier Registry)** ⏳ PENDING

Create `src/shared/skills/AttackTypes.luau`:
```lua
export type AttackPacket = {
    type: "damage" | "effect" | "heal" | "drain" | "knockback",
    damageType: string?, amount: number?, penetration: number?,
    effectId: string?, chance: number?, params: any?,
    poolType: string?, force: number?, direction: Vector3?,
}

export type AttackContext = {
    packets: { AttackPacket },
    sourceId: string,
    metadata: { skillId: string?, tags: {string}?, isCrit: boolean?, [string]: any }
}
```

**Step 2: Update CombatService**

Add `applyAttack()` method alongside existing damage application:
```lua
function CombatService.applyAttack(targetId: string, attack: AttackContext, sourceId: string)
    -- Process each packet: damage, effects, heals, drains
    -- See Section 6.3.5 for full implementation
end

function CombatService._applyDamagePacket(targetId: string, packet: AttackPacket, sourceId: string, metadata: any)
    -- Extract existing damage logic into packet processor
    -- Apply damage with type-specific resistances/armor
end
```

Keep existing `applyDamage()` for backward compatibility during migration.

**Step 3: Wire into Query Resolver (preparation for 8.1-8.2)**

This step happens after 8.2 when SkillMediator exists. For now, create placeholder:
```lua
-- In BaseSkill (server) - add after SkillMediator is implemented
function BaseSkill:resolveAttack(base: {damage: number, damageType: string}): AttackContext
    -- Will use SkillMediator.resolve("resolveAttack") once resolver is ready
    -- For now, return simple attack
    return {
        packets = {{type = "damage", damageType = base.damageType, amount = base.damage}},
        sourceId = self.casterId,
        metadata = {skillId = self.name, tags = self.config.tags}
    }
end
```

**Step 4: Migrate One Skill**

Update a simple skill (e.g., Punch) to use attack composition:
```lua
-- Before:
CombatService.applyDamage(targetId, damage, self.casterId)

-- After:
local attack = self:resolveAttack({damage = damage, damageType = "Physical"})
CombatService.applyAttack(targetId, attack, self.casterId)
```

**Step 5: Test & Validate**

- Verify damage values match old system
- Test with multiple damage types (once modifiers added)
- Confirm StatusEffectsService integration works

**Step 6: Add Modifiers (after 8.3 - Modifier Registry)**

Once ModifierRegistry exists, add sample modifiers:
- Fire conversion (see Section 6.3.4)
- Burn application from Fire damage
- Crit multiplier
- Wound effect from slash tag

**Step 7: Gradual Migration** ⏳ NEXT

Migrate remaining skills one-by-one:
- TripleStrike (planned next)
- ManaBall
- Other combat skills
- NPC attack skills

**Step 8: Deprecate Legacy Path** ⏳ FUTURE

Once all skills migrated:
- Mark `CombatService.applyDamage()` as deprecated
- Eventually remove it in favor of attack-only API

---

### 8.1 AttackResolver System ✅ **COMPLETED**

**Implementation Complete:**

Created `src/server/SkillsFramework/AttackResolver.luau` with unified attack composition resolver:
- `resolve()` function routes attack queries to appropriate handlers
- `resolveAttack()` builds attack compositions from base values
- Type-safe query contexts using inline types (compatible with existing `SkillQueryTypes`)
- Placeholder for modifier pipeline (will be wired in Section 8.3)

Updated `BaseSkill:resolveAttack()` to use AttackResolver:
- Builds `AttackQueryContext` with skill metadata
- Calls `AttackResolver.resolve()` for modifier support
- Converts query result to `AttackContext` for CombatService

**Naming:** Renamed from SkillMediator to AttackResolver to avoid confusion with `Stats.SkillMediator` (which handles cost/tempo queries).

**Status:** Resolver infrastructure complete. Ready for ModifierRegistry integration (Section 8.3).

---

### 8.2 Define the shared query shapes (server + client)

**Note:** Existing `SkillQueryTypes.luau` already provides query context types for stats/cost/tempo resolution. Attack query types are defined inline in SkillMediator for now. May consolidate later if needed.

1. Add a small shared module (e.g. `src/shared/skills/SkillQueryTypes.luau`) that defines:
  - `SkillQueryContext` – what a query looks like.
  - `SkillQueryResult` – what comes back.
  - `SkillModifier` – the modifier interface.

  Rough shape:

  ```lua
  export type SkillQueryContext = {
  	entityId: string,
  	skillId: string,
  	event: string, -- "resolveSkillCost" | "resolveSkillTempo" | ...
  	tags: { string }?,
  	step: number?,
  	metadata: { [string]: any }?,
  	base: { [string]: any },
  }

  export type SkillQueryResult = {
  	values: { [string]: any },
  	log: { string }?,
  }

  export type SkillModifier = {
  	id: string,
  	priority: number,
  	matches: (ctx: SkillQueryContext) -> boolean,
  	apply: (ctx: SkillQueryContext, result: SkillQueryResult) -> (),
  }
  ```

2. Reference this module from both server and client code (server: `Stats`/`Skills`; client: `StatsClient`/`SkillsClient`). The **types** should be identical on both sides.

### 8.2 Implement `SkillMediator.resolve` on the server

1. Create `src/server/Stats/SkillMediator.luau` that:
  - Requires the shared `SkillQueryTypes`.
  - Exposes `resolve(ctx: SkillQueryContext): SkillQueryResult`.
  - Internally:
    - Starts with `result.values = table.clone(ctx.base)`.
    - Pulls a list of modifiers for `ctx.entityId` + `ctx.event` (initially empty or hard‑coded).
    - Sorts modifiers by `priority` (once per entity/event if you want micro‑optimisation).
    - Runs `matches`/`apply` in order.

2. For the **first version**, don’t try to replace all existing logic:
  - Implement only `resolveSkillCost` via this path.
  - For other events, just return `ctx.base` untouched.

3. Adapt `BaseSkill:previewResourceCost` and/or `BaseSkill:applyResourceCost` to:
  - Build a `SkillQueryContext` from:
    - `self.casterId`, `self.name`, `self.config.tags`, combo step, timing info.
    - `base = { resource = baseResource, amount = cost }`.
  - Call `SkillMediator.resolve(ctx)`.
  - Use the returned `values.resource` / `values.amount` to drive the existing `StatsManager.removeFromPool` call.

This step gives you a single, formal entry point for cost resolution while still using `StatsManager` for the actual pool mutation.---

### 8.3 ModifierRegistry System ✅ **COMPLETED**

**Implementation Complete:**

Created `src/server/SkillsFramework/ModifierRegistry.luau`:
- Per-entity storage: `entityId` → `queryType` → array of modifiers
- Priority-ordered application (lower priority = applied first)
- Core API:
  - `register(entityId, queryType, modifier)` - Add modifier
  - `unregister(entityId, queryType, modifierId)` - Remove modifier
  - `clearEntity(entityId)` - Remove all modifiers (cleanup on death)
  - `getModifiers(entityId, queryType)` - Get all modifiers for query
  - `applyModifiers(entityId, queryType, ctx, result)` - Execute modifier pipeline

Updated `AttackResolver.resolveAttack()`:
- Now calls `ModifierRegistry.applyModifiers()` after building base packets
- Modifiers can transform attacks dynamically (split damage, add effects, etc.)

Created `src/server/SkillsFramework/SampleModifiers.luau` with 5 demo modifiers:
1. **Fire Conversion** (priority 50) - Convert 30% physical → fire on melee attacks
2. **Burn on Fire** (priority 100) - 30% chance to apply Burn when fire damage exists
3. **Crit Multiplier** (priority 10) - 200% damage on crits
4. **Wound on Slash** (priority 100) - 20% chance to apply Bleed on slash-tagged skills
5. **Life Drain** (priority 200) - Heal for 15% of total damage dealt

**Status:** Modifier system fully functional. Skills can now have dynamic attack transformations via registered modifiers.

**Next:** Test modifiers by registering them on player entities and validating packet transformations.

---

### 8.4 Add a minimal modifier registry (server) [RENAMED - SEE 8.3]

1. Create a `ModifierRegistry` module under `src/server/Stats/` or `src/server/Skills/` that:
  - Stores a per‑entity list of `SkillModifier`s, keyed by event name.
  - Exposes:
    - `register(entityId: string, event: string, modifier: SkillModifier)`.
    - `unregister(entityId: string, event: string, modifierId: string)`.
    - `getModifiers(entityId: string, event: string): { SkillModifier }`.

2. Update `SkillMediator.resolve` to:
  - Call `ModifierRegistry.getModifiers(ctx.entityId, ctx.event)`.
  - Apply those modifiers in order.

3. Implement 1–2 sample modifiers directly in code to validate the flow, for example:
  - "Blood Magic" style: convert mana cost to life.
  - "+X% increased cost" for a specific skill tag.

Hook these up in a temporary way (e.g. register them when a test passive or flag is present on the entity) to test.

### 8.4 Mirror the query API on the client (StatsClient)

1. Create or extend a client stats/metadata store (e.g. `src/client/Stats/StatsClient.luau`) to:
  - Maintain mirrored stats/pools using existing `StatsDelta` events.
  - Maintain per‑skill base data and tags via `SkillsMetadataService` events.

2. In that module, implement a **client** `resolve(ctx: SkillQueryContext): SkillQueryResult` that:
  - Starts with `ctx.base`.
  - Optionally applies a **subset** of modifiers known client‑side (e.g. basic passives, anything deducible from metadata).
  - Returns best‑effort predictions.

3. Change client‑side skill gating in `BasicComboSkill:use` / `canUseLocally` to:
  - Use `StatsClient.resolve` for predicting cost and tempo rather than ad‑hoc stat queries.
  - Still treat the server as authoritative and reconcile based on the server’s response.

This ensures the **same query shape** is used on both server and client, even if the math is approximated client‑side.

### 8.5 Harden and tag FX replication

1. In `src/client/fx/Replicator.luau`:
  - Remove the early `return` when `entityId` is nil; treat that as a world/"Server" FX and proceed through the non‑anchored branch.
  - Make `findAnchor` accept `entity: Model?` and return `nil` gracefully if `entity` is absent.
  - Optionally add a fallback to `FXPlayer.playAt` when an anchor is not found but `origin`/`offset` exists.

2. In `src/client/fx/FXPlayer.luau`:
  - Fix `spawnAt`'s `Stop` to use a small linger (e.g. `linger + 0.1`) instead of `+ 100`.

3. When emitting FX for at least one representative skill (e.g. Punch or Dash):
  - Include `{ skill = skillName, attemptId = attemptId }` in `payload.meta`.
  - Store that `meta` alongside the handle in `fxMap[entityId][fxKey]`.

These changes lay the groundwork for later "stop all FX for this (skill, attempt, entity)" logic.

### 8.6 Introduce a lightweight SkillAttempt store on the client

1. Add a client module (e.g. `src/client/SkillsFramework/AttemptStore.luau`) that tracks:
  - `{ [attemptId]: { skillId, casterId, state, createdAt, lastUpdate, step?, totalSteps?, reason? } }`.
  - Helper functions to transition states:
    - `beginLocal(skillId, casterId, step?, meta?)` → returns `attemptId`.
    - `markPending(attemptId)`.
    - `confirm(attemptData)`.
    - `reject(attemptId, reason)`.
    - `complete(attemptId, reason?)`.

2. Use this store in `BasicComboSkill:use` (or the new client skill driver) to:
  - Create an attempt when local prediction says "yes".
  - Attach `attemptId` to the request sent to the server.
  - Update the attempt based on server response and skill events.

3. Later, extend FX handling so that looped/shared FX can be stopped based on attempt completion or rejection.

### 8.7 Expand the query pipeline to more events

After cost queries are stable through `SkillMediator.resolve`, gradually:

1. Introduce more events:
  - `"resolveSkillTempo"` – for tempo/durationScale.
  - `"resolveSkillProjectiles"` – for projectile count/speed.
  - `"resolveSkillArea"` – for AoE radius and shape.

2. Migrate existing logic that lives in `SkillTimingService`, skills, or ad‑hoc stat lookups so that they call into `SkillMediator.resolve` instead of:
  - Directly touching `StatsMediator`.
  - Manually applying tag‑based tweaks.

3. As each area is migrated, delete or simplify the legacy code paths to avoid duplication.

### 8.8 Clean up deprecated paths

Once the above steps are in place for your core skills:

1. **Skills/FX cleanup**
  - Remove commented‑out or unused FX code in `SkillsClient`, `AnimationPlayer`, and skills themselves where the new FX replication path is in use.
  - Ensure shared FX for each migrated skill flows only through `FXReplicator`.

2. **Stats/mediator cleanup**
  - Remove or alias legacy `StatsMediator` entry points that have been fully replaced by `SkillMediator.resolve`.
  - Trim obsolete fields from stat configs and skill configs that were only used by old logic.

3. **Client mirror tightening**
  - Ensure client `StatsClient.resolve` and server `SkillMediator.resolve` share the same context/result types.
  - Adjust client prediction to rely exclusively on the mirrored resolver, rather than any direct stat reads, so behavior is easier to reason about.

This phase is mostly "debt repayment": deleting old code once you are confident the new systems are stable.

---

## 9.0 Combat UX & Polish (FUTURE - Post Migration)

**Status:** Deferred until after attack composition migration is complete.

### Issues to Address:

**Damage Feedback & Visibility:**
- Hard to determine how much damage is being applied
- No clear visual feedback for damage types (Physical vs Fire vs etc)
- No way to see modifier transformations in action
- Crit hits, converted damage, and drain effects are invisible

**EntityInfoService Performance:**
- Current implementation needs efficiency improvements
- Overhead health bars for all revealed entities may be costly
- Delta updates could be optimized
- Consider culling distant/irrelevant entities

**Projectile System Overhaul:**
- ProjectileService migration incomplete (client visuals + server logic separation)
- Projectile-based skills (ManaBall) currently broken/non-functional
- Need design time to architect proper client/server split
- Block projectile skill migration until this is resolved

### Proposed Improvements:

**Damage Numbers:**
- Floating damage text on hit (with type coloring)
- Separate display for crits, converted damage, drains
- Show modifier effects (e.g., "70 Physical + 30 Fire" on Fire Conversion)
- Animation/fade for damage numbers

**Combat Feedback:**
- Hit markers/sounds for successful attacks
- Visual effect on target (flash, outline, etc.)
- Health bar updates synchronized with damage events
- Status effect icons above enemy heads

**EntityInfo Optimization:**
- Spatial partitioning for presence updates
- Only stream entities within render distance
- Throttle delta updates (not every heartbeat)
- Pool overhead UI elements instead of creating/destroying

**Debug Tools:**
- Combat log panel showing packet transformations
- Modifier inspector to see active modifiers per entity
- Damage breakdown (base → final after all modifiers)

### Next Steps (When Ready):
1. Design damage number system (client-side only or replicated?)
2. Profile EntityInfoService to identify bottlenecks
3. Plan projectile architecture (separate doc)
4. Implement combat log for debugging modifier behavior

---

## 9.1 Damage Number System Implementation ⏳ **IN PROGRESS**

**Architecture:** Server-authoritative with hit-driven coordination. Numbers show when server confirms damage, coordinated with animation markers for melee skills.

**Design Decisions:**
- Server-only damage values (no client prediction due to dodge/armor/mitigation variance)
- Hit event drives display (works for melee, projectile, ranged, instant)
- Animation marker coordination for melee (numbers appear on impact frame)
- No marker coordination for projectile/ranged (show immediately on server response)
- 0.5s pooling window per damage type (prevents number spam on rapid hits)

### Phase 1: Server-Side AttackResult & Broadcasting

**Goal:** Return detailed damage breakdown from CombatService and broadcast to clients.

**Step 1.1: Extend AttackResult Type** ⏳
- Location: `src/server/Services/CombatService.luau`
- Add fields to existing DamageResult type:
  - `byType: { [string]: number }` - Damage breakdown by type
  - `blocked: boolean` - Was attack blocked
- Export as `AttackResult` for clarity

**Step 1.2: Track Damage by Type** ⏳
- In `_applyDamageInternal()`, accumulate damage per type
- In `applyAttack()`, iterate packets and build `byType` table
- Return complete AttackResult with all packet results

**Step 1.3: Add Combat Channel** ⏳
- Location: `src/shared/Networking/Channels.luau`
- Add `Combat` channel definition:
  - Direction: server_to_client
  - QoS: HIGH
  - Events: `["HitEvent"]`

**Step 1.4: Broadcast Hit Events** ⏳
- Location: `src/server/Services/CombatService.luau`
- Create `broadcastHit(sourceId, result)` function
- Call after each `applyAttack()` (or inside it)
- Emit HitEvent with: sourceId, targetId, result, timestamp

**Validation:** Server logs show HitEvent emissions with correct damage breakdowns.

---

### Phase 2: Client Hit Coordination

**Goal:** Coordinate server hit results with local events (markers, projectiles).

**Step 2.1: Create DamageNumberController** ⏳
- Location: `src/client/ui/DamageNumberController.luau`
- State storage:
  - `pendingHits: { [key]: PendingHit }` - Awaiting marker/result
  - `activeNumbers: { [key]: ActiveNumber }` - Currently displayed
- Core functions:
  - `registerLocalHit(sourceId, targetId, options)` - Register marker coordination
  - `onMarkerFired(sourceId, targetId)` - Animation marker reached
  - `onServerHit(event)` - Server result arrived
  - `showNumber(targetId, result)` - Display number
  - `cleanup(key, reason)` - Safety timeout

**Step 2.2: Hit Coordination Logic** ⏳
- If `hasMarker = true`:
  - Wait for both marker AND server result before showing
  - Show immediately if either arrives first, then when second arrives
- If `hasMarker = false` or no registration:
  - Show immediately when server result arrives
- Safety timeout: 0.5s max wait, show whatever we have

**Step 2.3: Listen to HitEvent** ⏳
- In DamageNumberController init
- Get dispatcher via `Networking.client()`
- Register listener: `dispatcher:on("HitEvent", onServerHit)`

**Validation:** Console logs show coordination working (marker fires, result arrives, number shows).

---

### Phase 3: Basic Number Display

**Goal:** Show floating numbers with a pop + rise + fade animation.

**Step 3.1: Create Number UI Template** [x]
- Template lives in `ReplicatedStorage/Assets/WorldUI/DamageLabel` (BillboardGui).
- Controller caches original size for reset after crit scaling.

**Step 3.2: Spawn Number Function** [x]
- `spawnNumber(targetId, amount, damageType, metadata)`
- Finds a spawn anchor named `DamageNumberSpawn*` (Attachment) or falls back to HumanoidRootPart.
- Applies random offset for a Warframe-style scatter.
- Uses GUI pooling (`guiPool`) to avoid churn.
- Animates pop-in, rise, and fade; returns GUI to pool on completion.

**Step 3.3: showNumber Implementation** [x]
- Spawns one number per damage type (no numeric pooling).
- Small stagger between types for readability.

**Validation:** Hit enemy, see colored numbers pop, rise, fade, and reuse pooled GUI.

---


### Phase 4: Animation Marker Integration

**Goal:** Melee skills coordinate damage numbers with impact frames.

**Step 4.1: Detect Impact Markers** ⏳
- Location: `src/client/Animation/AnimationPlayer.luau`
- In `playWithMarkers()` or wherever tracks are played:
- Check if track has "Impact" marker:
  ```lua
  local hasImpactMarker = false
  for _, marker in track:GetMarkers() do
      if marker.Name == "Impact" then
          hasImpactMarker = true
          break
      end
  end
  ```

**Step 4.2: Register Hits with Markers** ⏳
- When playing animation with Impact marker:
- Call `DamageNumberController:registerLocalHit(sourceId, targetId, { hasMarker = true })`
- Requires sourceId and targetId in animation metadata
- May need to pass this through SkillsClient → AnimationPlayer

**Step 4.3: Fire Marker Events** ⏳
- Connect to `track:GetMarkerReachedSignal("Impact")`
- When fired, call `DamageNumberController:onMarkerFired(sourceId, targetId)`
- Disconnect after first fire (or use Once pattern)

**Step 4.4: Pass Target Info Through Events** ⏳
- Update SkillsClient to extract targetId from skill events
- Pass to AnimationPlayer in metadata
- May require server to include targetId in HitEvent or SkillSession metadata (if hitting single target)
- For multi-target, may need different approach (show on all targets, or skip marker coordination)

**Validation:** Punch animation plays, marker fires, damage number appears right on impact frame.

---

### Phase 5: Damage Type Pooling (Removed)

Numeric pooling is intentionally not used (Warframe-style separate numbers).
Performance concerns are addressed via GUI object pooling in Phase 7.

**Status:** Removed from scope.

---


### Phase 6: Type-Specific Styling

**Goal:** Visual distinction between damage types and special cases.

**Step 6.1: Damage Type Colors** [x]
- Implemented `DAMAGE_COLORS` map in `DamageNumberController`.
- Applied to TextLabel.TextColor3 based on damageType.

**Step 6.2: Multi-Type Display** [x]
- Displays one number per damage type (`result.byType`).
- Uses slight stagger for readability.

**Step 6.3: Critical Hit Styling** [x]
- Adds exclamation marks and scales the BillboardGui for crit emphasis.

**Step 6.4: Special Cases** [ ]
- `dodged`/`blocked` placeholders exist, but no UI text yet.

**Validation:** Mixed damage types show distinct colors; crits show emphasis.

---

### Phase 7: Performance & Polish

**Goal:** Optimize for many simultaneous numbers, add final touches.

**Step 7.1: Number Pooling (Object Reuse)** [x]
- Pre-create pool of BillboardGuis
- Reuse instead of creating/destroying
- `getFromPool()` and `returnToPool()`
- Pool size: 50 (MAX_POOL_SIZE)

**Step 7.2: Distance Culling** ⏳
- Don't show numbers for enemies >100 studs away
- Check distance before spawning
- Reduces UI overhead for large battles

**Step 7.3: Settings Integration** ⏳
- Add user settings:
  - Enable/disable damage numbers
  - Damage number size multiplier
  - Show/hide mitigated amounts
  - Color scheme preference
- Store in client settings module

**Step 7.4: Animation Polish** ⏳
- Easing functions: Quart.Out for rise, Sine.InOut for fade
- Slight random X offset: prevents perfect overlap
- Optional: camera-relative positioning (always face camera)
- Sound effect on crit numbers (optional)

**Step 7.5: Performance Profiling** ⏳
- Test with 10+ enemies taking damage simultaneously
- Check for frame drops
- Optimize TweenService usage if needed
- Consider using RunService for custom animations if tweens too expensive

**Validation:** 
- Large battle with many enemies, numbers smooth
- Can toggle damage numbers off/on
- No memory leaks after extended play

---

### Phase 8: Integration Testing & Edge Cases

**Goal:** Ensure system works for all skill types and scenarios.

**Step 8.1: Melee Skills** ✅
- Punch: Single hit with marker
- TripleStrike: Three hits with markers (separate numbers)
- Combo chains: Numbers appear for each step

**Step 8.2: Projectile Skills** ⏳
- ManaBall (when fixed): Number on projectile collision
- No marker coordination needed
- Number shows when HitEvent arrives

**Step 8.3: Multi-Target Skills** ⏳
- AOE attacks hitting multiple enemies
- Each enemy gets own damage number
- Server sends multiple HitEvents
- Client handles each independently

**Step 8.4: Status Effect Damage** ⏳
- Burn/Poison tick damage
- Shows smaller numbers (75% size)
- Different color (slightly transparent)
- Minimal animation (no rise, just fade)

**Step 8.5: Edge Cases** ⏳
- Target dies before number shows: skip display
- Target disappears (player leaves): clean up pending
- Server lag >500ms: show number anyway (timeout)
- Multiple attackers hitting same target: separate numbers with slight X offset

**Validation:** All skill types show correct numbers in correct scenarios.

---

### Phase 9: Future Enhancements (Post-MVP)

**Optional improvements after basic system is stable:**

**9.1: Damage Number Customization**
- Player can choose font style
- Damage number themes (minimal, arcade, MMO-style)
- Custom colors per damage type

**9.2: Aggregate Display**
- "Total Damage" summary after combo
- "DPS meter" showing damage per second
- Damage breakdown UI panel (detail view)

**9.3: Advanced Effects**
- Particle effects on crit
- Screen shake on large damage
- Damage direction indicators (arrows)
- Overkill display (damage beyond death)

**9.4: Combat Log**
- Scrolling combat log in UI
- Shows all damage dealt/received
- Filter by type, source, target
- Export for analysis

**9.5: Accessibility**
- High contrast mode
- Larger text option
- Colorblind-friendly palette
- Reduce motion option

---

### Implementation Checklist

**Phase 1: Server (Foundation)**
- [x] 1.1 - Extend AttackResult type with byType field
- [x] 1.2 - Track damage by type in applyAttack()
- [x] 1.3 - Add Combat networking channel
- [x] 1.4 - Implement broadcastHit() and call on damage

**Phase 2: Client (Coordination)**
- [x] 2.1 - Create DamageNumberController module structure
- [ ] 2.2 - Implement hit coordination logic (marker + server) (deferred to Phase 4)
- [x] 2.3 - Register HitEvent listener

**Phase 3: Display (Basic)**
- [x] 3.1 - Create BillboardGui template
- [x] 3.2 - Implement spawnNumber() with fade animation
- [x] 3.3 - Implement showNumber() dispatcher

**Phase 4: Markers (Melee Timing)**
- [ ] 4.1 - Detect Impact markers in AnimationPlayer
- [ ] 4.2 - Register hits when markers present
- [ ] 4.3 - Fire onMarkerFired when marker reached
- [ ] 4.4 - Pass targetId through skill events

**Phase 5: Pooling (Rapid Hits) � removed**
- [x] Removed numeric pooling (Warframe-style per-hit numbers)

**Phase 6: Styling (Visual Polish)**
- [x] 6.1 - Add damage type color map
- [x] 6.2 - Handle multi-type damage display
- [x] 6.3 - Implement crit styling
- [ ] 6.4 - Add dodge/block/mitigated displays

**Phase 7: Performance (Optimization)**
- [x] 7.1 - Implement GUI object pooling
- [ ] 7.2 - Add distance culling
- [ ] 7.3 - Add user settings
- [ ] 7.4 - Polish animations with easing
- [ ] 7.5 - Performance profiling

**Phase 8: Testing (Validation)**
- [ ] 8.1 - Test all melee skills
- [ ] 8.2 - Test projectile skills
- [ ] 8.3 - Test multi-target scenarios
- [ ] 8.4 - Test status effect damage
- [ ] 8.5 - Test edge cases

**Phase 9: Future (Optional)**
- [ ] 9.1 - Customization options
- [ ] 9.2 - Aggregate displays
- [ ] 9.3 - Advanced effects
- [ ] 9.4 - Combat log
- [ ] 9.5 - Accessibility features


---

### Progress Tracking

**Current Phase:** Phase 7 - Performance (Optimization)  
**Current Step:** 7.2 - Distance culling  
**Status:** Phases 1-3 complete, Phase 5 removed, Phase 6 partially complete (6.4 pending)

**Completed:**
- Phase 1: AttackResult byType + HitEvent broadcast
- Phase 2.1/2.3: DamageNumberController + HitEvent listener
- Phase 3: Template + spawn/animation + showNumber
- Phase 6.1-6.3: Colors, multi-type, crit styling
- Phase 7.1: GUI object pooling

**In Progress:**
- Phase 7 performance pass (distance culling + profiling)

**Next Steps:**
- Add distance culling (skip far targets).
- Implement dodged/blocked display text (Phase 6.4).
- Optional: marker coordination (Phase 4).
- Run profiling and edge-case tests.

**Estimated Completion:**
- Phase 7 (Performance): 1-2 hours
- Phase 8 (Testing): 1-2 hours
- Optional Phase 4 (Markers): 1-2 hours






