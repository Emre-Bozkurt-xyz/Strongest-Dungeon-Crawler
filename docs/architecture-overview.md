# Strongest Dungeon Crawler - Architecture Overview

This document provides a comprehensive overview of the codebase architecture, covering server systems, client systems, and shared infrastructure.

---

## Table of Contents

1. [Architecture Principles](#architecture-principles)
2. [Server Systems](#server-systems)
   - [Stats System](#stats-system-srcserverstats)
   - [Skills Framework](#skills-framework-srcserverskillsframework)
   - [Services](#server-services-srcserverservices)
   - [Status Effects](#status-effects-srcserverstatuseffects)
   - [NPC Service](#npc-service-srcservernpcservice)
3. [Client Systems](#client-systems)
   - [Skills Framework](#client-skills-framework-srcclientskillsframework)
   - [FX System](#fx-system-srcclientfx)
   - [Animation System](#animation-system-srcclientanimation)
   - [UI Controllers](#ui-controllers-srcclientui)
   - [Stats Client](#stats-client-srcclientstats)
   - [Input System](#input-system-srcclientinput)
   - [Entity Management](#entity-management)
4. [Shared Systems](#shared-systems)
   - [Networking](#networking-srcsharednetworking)
   - [Skills Configuration](#skills-configuration-srcsharedskills)
   - [Stat Types](#stat-types-srcshared)
   - [Characters](#characters-srcsharedcharacters)
   - [Action Permissions](#action-permissions-srcsharedactionpermissions)
5. [Data Flow Diagrams](#data-flow-diagrams)
6. [Skill Execution Flow](#skill-execution-flow)
7. [Key Patterns & Conventions](#key-patterns--conventions)

---

## Architecture Principles

### Server Authority
- **All gameplay-affecting state is server-authoritative**: damage, cooldowns, execution locks, combo progression
- **Client predicts for responsiveness**: animations, FX, sounds play immediately without waiting for server
- **Reconciliation**: Server confirms or rejects client predictions; client adjusts state accordingly

### Entity-Based Design
- All entities (players + NPCs) are identified by unique `entityId` strings (GUIDs)
- The `Registrar` service maps entityIds to model instances and player references
- Stats, skills, and effects are all keyed by entityId

### Event-Driven Communication
- Custom `Dispatcher` networking layer with typed channels and QoS levels
- Delta-based state synchronization (only changes are sent)
- Request/response pattern for client-initiated actions

### Timing Model
- Uses `os.clock()` (monotonic) for all timing calculations
- Execution phase → Cooldown phase (cooldown starts AFTER execution completes)
- Tempo scaling: animations and skill durations scale based on stats (AttackSpeed, SpellCastSpeed)

---

## Server Systems

### Stats System (`src/server/Stats/`)

The stats system manages all character progression, combat values, and resource pools.

#### Key Files

| File | Purpose |
|------|---------|
| [StatsManager.luau](../src/server/Stats/StatsManager.luau) | Server-authoritative stat management; handles base values, modifiers, pools, and regeneration. Syncs to clients via dispatcher deltas. |
| [AttributesManager.luau](../src/server/Stats/AttributesManager.luau) | RPG-style attributes (Strength, Agility, etc.) with point allocation and modifier system |
| [StatsMediator.luau](../src/server/Stats/StatsMediator.luau) | Central query/observer layer with caching; provides hooks for stat modifications and computed values |
| [SkillMediator.luau](../src/server/Stats/SkillMediator.luau) | Resolves skill-specific stat queries (costs, damage) through modifier pipelines |
| [Config/StatsConfig.luau](../src/server/Stats/Config/StatsConfig.luau) | Default stat configurations (StatClass, PoolStatClass, ResourceStatClass) |

#### Key Concepts

**Stat Types:**
- **Static Stats**: Calculated values (PhysicalDamage, MagicDamage, AttackSpeed, Armor, CritChance)
- **Pool Stats**: Current/max values (Health, Mana, Stamina) with reservations
- **Resource Stats**: Hybrid pools with callbacks (Energy)

**Modifier System:**
- Modifiers have `source_id`, `type` (flat/percent), optional conditions
- Priority-based application order
- Support for strategies (custom modification logic)

**Query Flow:**
```
StatsManager.getStatValue(entityId, statType, queryOptions?)
    → StatsMediator.query() with caching
    → Observer hooks for modifications
    → Final computed value
```

#### Connections
- **SkillsManager** queries costs via `StatsManager.canSpendPool()`
- **CombatService** uses stats for damage calculations
- **RegenerationService** ticks pools based on regen stats
- **Client** receives delta events via `StatsDelta` dispatcher event

---

### Skills Framework (`src/server/SkillsFramework/`)

The skill system handles all combat abilities with execution phases, combos, and cooldowns.

#### Key Files

| File | Purpose |
|------|---------|
| [SkillsManager.luau](../src/server/SkillsFramework/SkillsManager.luau) | Entry point for skill use requests; handles gating, combo chaining, and session creation |
| [SessionManager.luau](../src/server/SkillsFramework/SessionManager.luau) | Unified skill session state, combo windows, transitions, and heartbeat expiry |
| [CooldownService.luau](../src/server/SkillsFramework/CooldownService.luau) | Per-skill cooldown + GCD management; mid-cooldown adjustment support |
| [HitboxService.luau](../src/server/SkillsFramework/HitboxService.luau) | Spatial queries (cone/sphere/box/ray) with faction filtering and debug visualization |
| [Timeline.luau](../src/server/SkillsFramework/Timeline.luau) | Generic scheduling system for timed sequences |
| [SkillTimingService.luau](../src/server/SkillsFramework/SkillTimingService.luau) | Resolves tempo based on skill tags and entity stats |
| [SkillsConfig.luau](../src/server/SkillsFramework/SkillsConfig.luau) | Loads declarative skill definitions; instantiates skill classes |
| [AttackResolver.luau](../src/server/SkillsFramework/AttackResolver.luau) | Processes attack packets (damage types, effects) |

#### Skill Class Hierarchy

```
BaseSkill (abstract)
├── BaseComboSkill (multi-step combo support)
│   └── Punch.luau (3-step combo)
└── Direct implementations
    ├── TripleStrike.luau (timeline-based multi-hit)
    ├── Dash.luau (movement skill)
    └── ManaBall.luau (projectile skill)
```

#### Execution Lifecycle

```
1. Client sends SkillRequestUse → SkillsManager.canUse()/useSkill()
2. Gating checks: ActionPermissions, cooldowns, session lock
3. SkillsManager creates/advances a SessionManager session (combo or single)
4. Skill.use() called:
   - BaseSkill:beginExecution() → SessionManager.transition(ACTIVE)
   - Schedule hits via Timeline or task.delay()
   - BaseComboSkill.extendComboWindow() updates session combo window
   - BaseSkill:completeExecution() → SessionManager.transition(COMPLETED)
5. SessionManager heartbeat handles expiry and emits SkillSession events
6. SkillsManager listens for terminal sessions → start cooldown + GCD
```

#### Combo System

**Key Concepts:**
- Combo state is stored on the session (`session.combo`)
- `SessionManager.advanceCombo()` increments step and stepToken
- `SessionManager.extendComboWindow()` sets windowOpensAt/windowExpiresAt
- **Window gating**: Next step only allowed within the authoritative window

**Timing Parameters:**
- `hitDelays`: When damage applies within each step
- `stepDelays`: Minimum time before next step input allowed
- `recovery`: Post-final-hit lock before execution completes
- `window`: Duration input is accepted after step completes

#### Connections
- **CombatService** receives damage requests from skill hit logic
- **StatsManager** provides cost resolution and stat queries
- **Dispatcher** sends `SkillSession`, `CooldownEvents`, and `HitEvent` to clients

---

### Server Services (`src/server/Services/`)

Core gameplay services beyond skills and stats.

#### Key Files

| File | Purpose |
|------|---------|
| [Registrar.luau](../src/server/Services/Registrar.luau) | Entity registry; maps GUIDs to models/players. Foundation for all entityId-based systems |
| [CombatService.luau](../src/server/Services/CombatService.luau) | Damage application using stat-derived values; dodge, crit, armor, shield absorption |
| [StaggerSystem.luau](../src/server/Services/StaggerSystem.luau) | Applies stagger status effects based on damage thresholds |
| [StaggerCalculator.luau](../src/server/Services/StaggerCalculator.luau) | Computes dynamic stagger values from entity stats and CharacterSpecs |
| [EntityInfoService.luau](../src/server/Services/EntityInfoService.luau) | Streams presence info to clients based on Perception stats |
| [RegenerationService.luau](../src/server/Services/RegenerationService.luau) | Ticks pool regeneration (30Hz internally, 2Hz to clients) |
| [FXReplicator.server.luau](../src/server/Services/FXReplicator.server.luau) | Relays FX events between clients |

#### Registrar API

```lua
-- Server-side entity registration
local entityId = Registrar.registerEntity(model, isPlayer?)
Registrar.unregisterEntity(model)

-- Lookups
Registrar.getEntityId(model) → string?
Registrar.getEntityById(entityId) → Model?
Registrar.getPlayerId(player) → string?
Registrar.getPlayerById(entityId) → Player?
Registrar.isPlayerEntity(entityId) → boolean
```

#### Combat Flow

```
AttackResolver.resolve(attack) 
    → CombatService.applyAttack(targetId, attack, sourceId)
        → Dodge check (target stat)
        → Crit check (source stat)
        → Armor mitigation
        → Shield absorption
        → Health damage
        → StaggerSystem.tryStagger()
        → Emit HitEvent to clients
```

#### Connections
- **SkillsFramework** calls CombatService for damage
- **StatusEffectsService** can trigger damage via ticks (DoTs)
- **Clients** receive `HitEvent` for damage numbers and feedback

---

### Status Effects (`src/server/StatusEffects/`)

Timed buffs/debuffs with complex stacking behaviors.

#### Key Files

| File | Purpose |
|------|---------|
| [StatusEffectsService.luau](../src/server/StatusEffects/StatusEffectsService.luau) | Register, apply, tick, and remove effects with stacking rules |
| [EffectsIndex.luau](../src/server/StatusEffects/EffectsIndex.luau) | Central catalog of effect definitions |
| [Blocking/](../src/server/StatusEffects/Blocking/) | Blocking-specific effects (stagger, stun) |

#### Stacking Modes

| Mode | Behavior |
|------|----------|
| `aggregate` | Single stack with combined params; refresh resets duration |
| `multi` | Multiple independent entries; each has own timer/params |
| `charges` | Stack counter; independent or shared timers |

#### Duration Policies

| Policy | Behavior |
|--------|----------|
| `refresh` | Reapply resets duration to full |
| `extend` | Reapply adds to remaining duration |
| `independent` | Each stack has its own timer |

#### Effect Definition Shape

```lua
{
    id = "Burn",
    duration = 5,
    maxStacks = 5,
    tickInterval = 1,
    stacking = "multi",
    durationPolicy = "independent",
    capPolicy = "refreshWeakest",
    blocksActions = { cast = true, move = true }, -- Action blocking
    onApply = function(target, source, params, stacks) end,
    onTick = function(target, source, params, stacks, dt, ctx) end,
    onRemove = function(target, source, stacks) end,
}
```

#### Connections
- **ActionPermissions** queries `hasBlockingEffect()` for action gating
- **CombatService** provides `applyAttack` context for DoT effects
- **StaggerSystem** applies the "stagger" effect

---

### NPC Service (`src/server/NPCService/`)

Component-based NPC management system.

#### Key Files

| File | Purpose |
|------|---------|
| [NPCManager.luau](../src/server/NPCService/NPCManager.luau) | Core NPC registry; component management using native Roblox storage (Attributes + Folders) |
| [ComponentManager.luau](../src/server/NPCService/ComponentManager.luau) | Orchestrates component updates without circular dependencies |
| [NPCSpawner.luau](../src/server/NPCService/NPCSpawner.luau) | Spawns prefabs and attaches component sets |
| [NPCAnimationController.luau](../src/server/NPCService/NPCAnimationController.luau) | Animation playback for NPCs |
| [Components/](../src/server/NPCService/Components/) | Individual component implementations |
| [NPCPrefabs/](../src/server/NPCService/NPCPrefabs/) | NPC configuration templates |

#### Component System

Components are stored as Folders under `Model/Components/`:
```
NPCModel/
├── Components/
│   ├── Movement/   (__active = true)
│   ├── Combat/
│   ├── Behavior/
│   └── Damageable/
```

**Built-in Components:**
- `Movement`: Pathfinding and locomotion
- `Combat`: Attack behavior and targeting
- `Behavior`: AI state machine (BehaviorToolkit)
- `Damageable`: Health and damage reception

#### NPCManager API

```lua
NPCManager.register(model, options?) → entityId
NPCManager.unregister(model)
NPCManager.addComponent(model, "Combat") → Folder
NPCManager.hasComponent(model, "Combat") → boolean
NPCManager.getComponent(model, "Combat") → Folder?
NPCManager.getNPCsWithComponent("Combat") → { Model }
```

#### Connections
- **Registrar** provides entityId for each NPC
- **StatsManager** manages NPC stats (with `skipSync = true` for non-player entities)
- **ComponentManager.updateAll()** called each heartbeat

---

## Client Systems

### Client Skills Framework (`src/client/SkillsFramework/`)

Client-side skill prediction, state tracking, and server communication.

#### Key Files

| File | Purpose |
|------|---------|
| [SkillsClient.luau](../src/client/SkillsFramework/SkillsClient.luau) | Initializes skills, listens for terminal sessions, and stops FX/animations |
| [CooldownClient.luau](../src/client/SkillsFramework/CooldownClient.luau) | Mirrors server cooldown state via dispatcher events |
| [SessionMirror.luau](../src/client/SkillsFramework/SessionMirror.luau) | Mirrors authoritative skill sessions and supports prediction |
| [ComboStateClient.luau](../src/client/SkillsFramework/ComboStateClient.luau) | Helper for combo gating using SessionMirror state |
| [SkillMetadataClient.luau](../src/client/SkillsFramework/SkillMetadataClient.luau) | Caches skill configuration sent from server |
| [AttemptStore.luau](../src/client/SkillsFramework/AttemptStore.luau) | Tracks skill use attempts for reconciliation |
| [SkillSlots.luau](../src/client/SkillsFramework/SkillSlots.luau) | Manages equipped skill slots |
| [SkillSlotUI.luau](../src/client/SkillsFramework/SkillSlotUI.luau) | UI for skill slot display with cooldown overlays |

#### Client Skill Classes (`Skills/`)

```
BaseSkill.luau (client)
├── BasicSkill.luau (single-use skills)
└── BasicComboSkill.luau (combo skills)
```

**BaseSkill** provides:
- Pre-flight validation (`canUseLocally()`)
- Animation playback via `AnimationCoordinator`
- FX binding via marker events
- Server request with success/failure callbacks

#### Prediction Flow

```
1. Input triggers skill.use()
2. canUseLocally() checks: ActionPermissions, cooldown, GCD, resources
3. ComboStateClient.canAdvance() gates combo windows (SessionMirror)
4. If valid:
   - SessionMirror.predictStart() creates a predicted session
   - playCastSoundLocal() + playAnimation() start immediately
   - requestUseAsync() sends non-blocking server request
5. Server response:
   - Success: SessionMirror updates authoritative session
   - Failure/Cancel: cancelLocalPrediction() stops visuals
```

#### ComboStateClient Logic

```lua
ComboStateClient.canAdvance(skillName) → (bool, reason?)
ComboStateClient.predictNextStep(skillName, totalSteps) → number
ComboStateClient.getCurrentStep(skillName) → number?
ComboStateClient.isActive(skillName) → boolean
```

---

### FX System (`src/client/fx/`)

Visual and audio effects with pooling and replication.

#### Key Files

| File | Purpose |
|------|---------|
| [FXPlayer.luau](../src/client/fx/FXPlayer.luau) | Plays particle/sound FX by key; pooling and automatic cleanup |
| [Replicator.luau](../src/client/fx/Replicator.luau) | FX event emission and reception for cross-client replication |
| [AnimationPlayer.luau](../src/client/fx/AnimationPlayer.luau) | Animation track loading with tempo scaling |
| [ImmediateHitFeedback.luau](../src/client/fx/ImmediateHitFeedback.luau) | Client-side hit detection for immediate visual feedback (flash, sound) |
| [ClientHitDetection.luau](../src/client/fx/ClientHitDetection.luau) | Lightweight cone/sphere queries for UX responsiveness |

#### FXPlayer API

```lua
-- One-shot at position
FXPlayer.playAt(key, cframe, lifetime?)

-- One-shot attached to anchor
FXPlayer.playAttached(key, attachment, offset?, lifetime?)

-- Spawn long-lived (returns handle with Stop())
FXPlayer.spawnAttached(key, attachment, offset?) → FXHandle?
```

#### Immediate Feedback Pattern

**Problem**: Waiting for server confirmation creates input lag
**Solution**: Client-side hit detection for immediate feedback

```lua
-- On animation impact marker:
ImmediateHitFeedback.onImpactMarker({
    hitSounds = { "rbxassetid://..." },
    coneAngle = 60,
    coneRange = 8,
})
    → ClientHitDetection.queryCone() finds targets
    → Flash targets (Highlight effect)
    → Play hit sound at position
    → Camera shake
```

**Note**: This is purely for UX. Server remains authoritative for actual damage.

---

### Animation System (`src/client/Animation/`)

#### Key Files

| File | Purpose |
|------|---------|
| [AnimationCoordinator.luau](../src/client/Animation/AnimationCoordinator.luau) | Central coordinator for skill animations; publishes marker events |

#### AnimationCoordinator

Wraps `AnimationPlayer` with semantic marker event publishing:

```lua
-- Play skill animation
AnimationCoordinator.playSkillAnimation(skillName, animKey, opts) → handle

-- Subscribe to marker events
AnimationCoordinator.onSkillMarker(skillName, markerName, callback) → disconnect

-- Markers fire when animation keyframes are reached
-- Used to trigger FX, sounds, hit detection at precise moments
```

**Options:**
- `fade`: Transition time
- `duration`: Target duration (calculates speed from native length)
- `tempo`: Speed multiplier

---

### UI Controllers (`src/client/ui/`)

UI state management driven by dispatcher events.

#### Key Files

| File | Purpose |
|------|---------|
| [DamageNumberController.luau](../src/client/ui/DamageNumberController.luau) | Floating damage numbers, crit flash, stagger animations (server-authoritative feedback) |
| [controllers/HealthBarController.luau](../src/client/ui/controllers/HealthBarController.luau) | Player health bar updates |
| [controllers/ManaBarController.luau](../src/client/ui/controllers/ManaBarController.luau) | Player mana bar updates |
| [controllers/StaminaBarController.luau](../src/client/ui/controllers/StaminaBarController.luau) | Player stamina bar updates |
| [controllers/AttributesUIController.luau](../src/client/ui/controllers/AttributesUIController.luau) | Attribute point allocation UI |
| [controllers/OverheadHealthBarController.luau](../src/client/ui/controllers/OverheadHealthBarController.luau) | World-space health bars for entities |

#### UI Pattern

```lua
-- Controller listens to dispatcher events
local HealthBarController = {}

function HealthBarController.new(Parent)
    local self = { ... }
    
    -- Bind to StatsDelta events
    StatsClient.onChanged(function(deltaType, target, data)
        if target == "Health" then
            self:updateHealth(data.currentValue, data.maxValue)
        end
    end)
    
    return self
end
```

---

### Stats Client (`src/client/Stats/`)

#### Key Files

| File | Purpose |
|------|---------|
| [ClientStatsStore.luau](../src/client/Stats/ClientStatsStore.luau) | Unified readonly facade over client stats + skill metadata |

**Provides:**
- `getPoolCurrent(poolType)` / `getPoolMax(poolType)`
- `getSkillMetadata(skillName)`
- `canAfford(skillName, step?)` - affordability check with cost info
- `onStatsChanged(callback)` - subscribe to stat updates

Also uses:
- [StatsClient.luau](../src/client/StatsClient.luau) - Receives `StatsDelta` events
- [AttributesClient.luau](../src/client/AttributesClient.luau) - Receives `AttributesDelta` events

---

### Input System (`src/client/input/`)

Action-based input binding with context switching.

#### Key Files

| File | Purpose |
|------|---------|
| [InputManager.luau](../src/client/input/InputManager.luau) | Action binding dispatcher built on UserInputService |
| [ActionConfig.luau](../src/client/input/ActionConfig.luau) | Declarative action definitions with key mappings |

#### ActionConfig Structure

```lua
{
    contexts = {
        Core = {
            name = "Core",
            enabled = true,
            priority = 100,
            actions = {
                Skill1 = {
                    name = "Skill1",
                    bindings = {
                        { key = Enum.KeyCode.One, type = "press" },
                        { mouse = Enum.UserInputType.MouseButton1, type = "press" },
                    },
                },
                -- ...
            },
        },
    },
}
```

#### InputManager API

```lua
-- Subscribe to action
InputManager.on("Skill1", function(actionName, bindingMeta)
    -- Handle skill activation
end)

-- Enable/disable context
InputManager.setContextEnabled("Core", false)

-- Rebind action (for settings)
InputManager.rebind("Skill1", newBinding)
```

---

### Entity Management

#### Key Files

| File | Purpose |
|------|---------|
| [ClientRegistrar.luau](../src/client/ClientRegistrar.luau) | Client-side entity registry using CollectionService |
| [EntityRevealStore.luau](../src/client/EntityRevealStore.luau) | Caches presence/reveal deltas from server |
| [EntityInfoClient.luau](../src/client/EntityInfoClient.luau) | Processes EntityInfoDelta events |
| [OverheadHealthService.luau](../src/client/OverheadHealthService.luau) | Spawns world-space HP bars for revealed entities |
| [WorldGUIManager.luau](../src/client/WorldGUIManager.luau) | Centralizes camera-facing world panels |

#### Reveal System

Server's `EntityInfoService` streams presence info based on player's Perception stats:

```
Server: EntityInfoService.tickPlayer()
    → Collects entities within perception radius
    → Applies reveal tier (hpPerc, full hp, etc.)
    → Emits EntityInfoDelta

Client: EntityRevealStore.onPresence(callback)
    → Caches revealed entities
    → Notifies subscribers (OverheadHealthService, etc.)
```

---

## Shared Systems

### Networking (`src/shared/Networking/`)

Custom dispatcher-based networking layer.

#### Key Files

| File | Purpose |
|------|---------|
| [Dispatcher.luau](../src/shared/Networking/Dispatcher.luau) | Core event/request dispatcher with stats and replay support |
| [Channels.luau](../src/shared/Networking/Channels.luau) | Channel definitions (QoS, direction, events, intents) |
| [ChannelRegistry.luau](../src/shared/Networking/ChannelRegistry.luau) | Channel registration and lookup |
| [Client.luau](../src/shared/Networking/Client.luau) | Client-side dispatcher wrapper |
| [Server.luau](../src/shared/Networking/Server.luau) | Server-side dispatcher wrapper |
| [Envelope.luau](../src/shared/Networking/Envelope.luau) | Message envelope structure |
| [Stats.luau](../src/shared/Networking/Stats.luau) | Network statistics tracking |
| [ReplayBuffer.luau](../src/shared/Networking/ReplayBuffer.luau) | Message replay for debugging |

#### QoS Levels

| Level | Use Case |
|-------|----------|
| `CRITICAL` | Skills, cooldowns - must not be dropped |
| `HIGH` | Interactive UI (attributes), FX |
| `NORMAL` | General gameplay |
| `BACKGROUND` | Entity presence, periodic updates |

#### Channel Definition

```lua
Skills = {
    remote = "Skills",
    remoteEvent = "SkillsEvent",
    remoteFunction = "SkillsRequest",
    direction = "bidirectional",
    qos = "CRITICAL",
    intents = { "SkillsRequest", "SkillRequestUse", "SkillMetadataSnapshot" },
    events = { "SkillsUpdate", "SkillMetadataUpdate" },
}

SkillSession = {
    remote = "SkillSession",
    remoteEvent = "SkillSessionEvent",
    remoteFunction = nil,
    direction = "server_to_client",
    qos = "CRITICAL",
    intents = nil,
    events = { "SkillSession" },
}
```

#### Dispatcher API

```lua
-- Events (fire-and-forget)
dispatcher:emit(eventName, payload, options?)
dispatcher:on(eventName, handler) → disconnect

-- Requests (response expected)
dispatcher:request(intentName, payload, options?) → response
dispatcher:onRequest(intentName, handler)
```

---

### Skills Configuration (`src/shared/skills/`)

#### Key Files

| File | Purpose |
|------|---------|
| [ClientSpec.luau](../src/shared/skills/ClientSpec.luau) | Visual configuration per skill (animations, FX, sounds) |
| [SkillTimingResolver.luau](../src/shared/skills/SkillTimingResolver.luau) | Maps skill tags → stat type → tempo calculation |
| [AttackTypes.luau](../src/shared/skills/AttackTypes.luau) | Attack packet structure definitions |
| [SkillQueryTypes.luau](../src/shared/skills/SkillQueryTypes.luau) | Query context types for SkillMediator |
| [AttemptState.luau](../src/shared/skills/AttemptState.luau) | Attempt tracking state structure |

#### ClientSpec Structure

```lua
Punch = {
    class = "BasicComboSkill",
    icon = "rbxassetid://...",
    label = "Punch",
    tags = { "melee", "light" },
    combo = {
        steps = 3,
        window = 0.6,
        stepDurations = { 0.45, 0.4, 0.5 },
    },
    anim = {
        comboSteps = {
            { key = "Punch_Combo_1" },
            { key = "Punch_Combo_2" },
            { key = "Punch_Combo_3" },
        },
    },
    fx = {
        anchor = { name = "FX_Hand_R" },
        markers = {
            punch_windup_start = { key = "Punch_Windup", action = "start" },
            Punch_Land = { key = "Punch_Land", isHitMarker = true },
        },
    },
    hitSounds = { "rbxassetid://..." },
    castSounds = { "rbxassetid://..." },
    hitConeAngle = 70,
    hitConeRange = 6,
}
```

#### SkillTimingResolver

Maps skill tags to tempo stats:
- `melee`, `attack`, `physical` → AttackSpeed
- `spell`, `magic`, `cast` → SpellCastSpeed

```lua
local result = SkillTimingResolver.resolve(skillTags, statLookup)
-- Returns: { tempo, durationScale, statType }
```

---

### Stat Types (`src/shared/`)

#### Key Files

| File | Purpose |
|------|---------|
| [StatTypes.luau](../src/shared/StatTypes.luau) | Single source of truth for all stat type definitions |
| [StatClass.luau](../src/shared/StatClass.luau) | Base stat class (static stats) |
| [PoolStatClass.luau](../src/shared/PoolStatClass.luau) | Pool stats (Health, Mana) with current/max |
| [ResourceStatClass.luau](../src/shared/ResourceStatClass.luau) | Hybrid pools with callbacks |
| [AttributeClass.luau](../src/shared/AttributeClass.luau) | RPG attributes (Strength, etc.) |
| [StatTypeUtil.luau](../src/shared/StatTypeUtil.luau) | Serialization and delta type utilities |

#### Type Architecture

```
StatTypes.luau
├── StaticStatType: "PhysicalDamage" | "MagicDamage" | ...
├── PoolType: "Health" | "Mana" | ...
├── ResourceStatType: "Energy"
├── StatType = StaticStatType | PoolType | ResourceStatType
└── EntityStats = { [string]: StatInstance | PoolInstance | ... }
```

---

### Characters (`src/shared/Characters/`)

Character specifications for visual configuration and combat properties.

#### Key Files

| File | Purpose |
|------|---------|
| [Types.luau](../src/shared/Characters/Types.luau) | CharacterSpec type definitions |
| [CharacterSpecRegistry.luau](../src/shared/Characters/CharacterSpecRegistry.luau) | Spec loading and caching |
| [PlayerCharacter.luau](../src/shared/Characters/PlayerCharacter.luau) | Default player spec |
| [NPCs/](../src/shared/Characters/NPCs/) | NPC-specific specs |

#### CharacterSpec Shape

```lua
{
    id = "PlayerCharacter",
    displayName = "Player",
    animations = {
        hit_light = "rbxassetid://...",
        stagger = "rbxassetid://...",
        death = "rbxassetid://...",
    },
    stagger = {
        threshold = 50,
        duration = 0.5,
        cooldown = 2,
        maxStackDamage = 200,
        canInterruptSkills = true,
    },
    sounds = {
        hit = { "rbxassetid://..." },
    },
}
```

---

### Action Permissions (`src/shared/ActionPermissions/`)

Permission query system for action gating.

#### Key Files

| File | Purpose |
|------|---------|
| [Types.luau](../src/shared/ActionPermissions/Types.luau) | Action types and block reasons |
| [Server.luau](../src/shared/ActionPermissions/Server.luau) | Server-side permission checks |
| [Client.luau](../src/shared/ActionPermissions/Client.luau) | Client-side prediction checks |

#### Action Types

- `cast`: Using skills
- `move`: Character movement
- `jump`: Jumping
- `dodge`: Dodge/roll
- `interact`: Object interaction

#### Server Check Flow

```lua
permissions:canCast(entityId)
    → Check if dead (Health <= 0)
    → Check execution lock
    → Check blocking status effects (stagger, stun, etc.)
    → Return (canPerform, blockReason?)
```

---

## Data Flow Diagrams

### Skill Use Flow

```
┌──────────┐    SkillRequestUse    ┌──────────────┐
│  Client  │ ─────────────────────→│    Server    │
│          │                       │              │
│ 1. Input │                       │ 2. Validate  │
│ 2. Predict│                      │ 3. Execute   │
│ 3. Animate│                      │ 4. Apply dmg │
│ 4. Request│                      │              │
└──────────┘                       └──────────────┘
     ↑                                    │
     │    SkillSession, HitEvent,         │
     │    CooldownEvents                  │
     └────────────────────────────────────┘
```

### Stats Update Flow

```
┌────────────┐   setBaseStat()   ┌────────────────┐
│   Server   │ ─────────────────→│  StatsManager  │
│   Logic    │                   │                │
└────────────┘                   │ • Update value │
                                 │ • Mark dirty   │
                                 └────────────────┘
                                        │
                              StatsDelta │ (dispatcher)
                                        ↓
┌────────────┐                   ┌────────────────┐
│   Client   │←──────────────────│  StatsClient   │
│   UI       │                   │                │
│            │←──onChanged()─────│ • Update cache │
└────────────┘                   └────────────────┘
```

### Entity Presence Flow

```
┌─────────────────┐  Heartbeat   ┌────────────────────┐
│ EntityInfoService│─────────────→│ For each player:   │
│    (Server)     │              │ • Query nearby     │
└─────────────────┘              │ • Apply reveal tier│
                                 │ • Emit delta       │
                                 └────────────────────┘
                                        │
                            EntityInfoDelta
                                        ↓
┌────────────────────┐           ┌────────────────────┐
│ EntityRevealStore  │←──────────│ OverheadHealthSvc  │
│    (Client)        │           │    (Client)        │
│ • Cache presence   │──notify──→│ • Create/update    │
│ • TTL pruning      │           │   HP bars          │
└────────────────────┘           └────────────────────┘
```

---

## Skill Execution Flow

This section details the complete flow from user input to skill execution, including all validation checks and services involved.

### Overview Diagram

```
Client:
1) Input triggers skill.use()
2) BaseSkill:canUseLocally() + ComboStateClient.canAdvance()
3) SessionMirror.predictStart() + play animation/FX immediately
4) requestUseAsync() sends SkillRequestUse

Server:
5) SkillsManager.canUse() checks cooldown + ActionPermissions
6) SkillsManager.useSkill() creates/advances SessionManager session
7) BaseSkill:beginExecution() -> SessionManager.transition(ACTIVE)
8) HitboxService/CombatService apply damage
9) BaseSkill:completeExecution() -> SessionManager.transition(COMPLETED)

Client reconcile:
10) SessionMirror receives SkillSession events
11) SkillsClient/AnimationCoordinator/Replicator stop or adjust visuals
```

### Key Services Involved

| Service | Location | Role |
|---------|----------|------|
| [InputManager](../src/client/Input/InputManager.luau) | Client | Binds key presses to skill slot actions |
| [BasicComboSkill](../src/client/SkillsFramework/Skills/BasicComboSkill.luau) | Client | Client-side combo skill with prediction |
| [BaseSkill](../src/client/SkillsFramework/Skills/BaseSkill.luau) | Client | `canUseLocally()` pre-flight validation |
| [SessionMirror](../src/client/SkillsFramework/SessionMirror.luau) | Client | Mirrors authoritative session state |
| [ComboStateClient](../src/client/SkillsFramework/ComboStateClient.luau) | Client | Combo gating based on SessionMirror windows |
| [CooldownClient](../src/client/SkillsFramework/CooldownClient.luau) | Client | Mirrors cooldown state |
| [SkillsManager](../src/server/SkillsFramework/SkillsManager.luau) | Server | Entry point, orchestrates all server checks |
| [ActionPermissions](../src/shared/ActionPermissions/Server.luau) | Server | Checks death, status effects, execution lock |
| [CooldownService](../src/server/SkillsFramework/CooldownService.luau) | Server | Per-skill and GCD cooldown management |
| [SessionManager](../src/server/SkillsFramework/SessionManager.luau) | Server | Unified session state, combo windows, expiry |
| [HitboxService](../src/server/SkillsFramework/HitboxService.luau) | Server | Spatial queries for hit detection |
| [CombatService](../src/server/Services/CombatService.luau) | Server | Damage application, crit, armor, etc. |

### Validation Checks (in order)

**Client-side (pre-flight, for responsiveness):**
1. `ComboStateClient.canAdvance()` - Is combo window open?
2. `BaseSkill:canUseLocally()`:
   - `ActionPermissions.client():canCast()` - Uses SessionMirror lock state
   - `CooldownClient.getRemaining()` - Is skill on cooldown?
   - `CooldownClient.getRemaining("_GCD")` - Is GCD active?
   - `ClientStatsStore.canAfford()` - Has enough resources?

**Server-side (authoritative):**
1. `CooldownService.isOnCooldown()` - Authoritative cooldown check
2. `ActionPermissions:canCast()`:
   - Is entity dead? (Health <= 0)
   - Is entity executing another skill? (allows combo chaining for same skill)
   - Does entity have blocking status effects? (stagger, stun)
3. `SessionManager.advanceCombo()` - Validates combo window and step sequencing

### Combo Chaining

Combo skills can "chain" (re-use while executing) because:

1. **ActionPermissions** accepts `{ skillName, isCombo }` options
2. If `isCombo=true` and `skillName` matches the active session, the lock is bypassed
3. **SessionManager** enforces timing windows (windowOpensAt/windowExpiresAt)

```lua
-- ActionPermissions:canCast() with combo support
permissions:canCast(entityId, {
    skillName = "Punch",
    isCombo = true,
})
```

### Rejection Handling

If the server rejects a skill request:
1. `BasicComboSkill` rejection callback is called
2. `BaseSkill.cancelLocalPrediction()` stops animation/FX immediately
3. Client may show rejection feedback (UI flash, sound)

Common rejection reasons:
- `on_cooldown` - Skill cooldown active
- `locked` - Another skill/session is active (and not combo chaining)
- `dead` - Entity is dead
- `stagger` / `stun` - Blocking status effect active
- `combo_busy` - Within combo busy window (client-side)
- `combo_expired` - Combo window closed (client-side)

---

## Key Patterns & Conventions

### Timing

- **Always use `os.clock()`** (monotonic) for timing logic
- **Never use `tick()`** (wall time) - causes issues with client/server sync

### Execution Lifecycle

- **Cooldown starts AFTER execution completes** (not at skill start)
- **Execution lock** prevents other skills during active phase
- **Combo chaining** is an exception: same skill can chain during execution

### Prediction vs Authority

| Client Does (Immediate) | Server Does (Authoritative) |
|------------------------|----------------------------|
| Play animation | Apply damage |
| Play sounds | Start cooldown |
| Show FX | Advance combo state |
| Flash targets | Apply status effects |
| Camera shake | Validate resources |

### Entity IDs

- All systems use `entityId: string` (GUID) as the primary key
- `Registrar` is the single source of truth for ID ↔ Instance mapping
- Player entityIds are also mapped to `Player` objects

### Dispatcher Events vs Requests

| Use Events For | Use Requests For |
|---------------|------------------|
| One-way notifications | Actions needing confirmation |
| State deltas | Server validation required |
| Broadcast updates | Response data needed |

### Module Organization

```
src/
├── server/           # Server-only code
│   ├── Services/     # Core gameplay services
│   ├── Stats/        # Stats management
│   ├── SkillsFramework/  # Skill execution
│   ├── StatusEffects/    # Buff/debuff system
│   └── NPCService/   # AI characters
├── client/           # Client-only code
│   ├── fx/           # Visual effects
│   ├── ui/           # UI controllers
│   ├── input/        # Input handling
│   ├── SkillsFramework/  # Client skill prediction
│   └── Stats/        # Client stat cache
└── shared/           # Shared between both
    ├── Networking/   # Dispatcher system
    ├── skills/       # Skill configurations
    ├── Characters/   # Character specs
    └── *.luau        # Stat types, utilities
```

---

## Quick Reference

### Adding a New Skill

1. Define in `src/server/SkillsFramework/SkillsData/SkillName.luau`
2. Create class in `src/server/SkillsFramework/Skills/SkillName.luau`
3. Add client spec in `src/shared/skills/ClientSpec.luau`
4. Add animations under `ReplicatedStorage/Assets/Animations/`
5. Add FX under `ReplicatedStorage/Assets/FX/`

### Adding a New Stat

1. Add type to `src/shared/StatTypes.luau`
2. Configure default in `src/server/Stats/Config/StatsConfig.luau`
3. If pool: add regeneration mapping in `RegenerationService.luau`

### Adding a Status Effect

1. Define in `src/server/StatusEffects/EffectsIndex.luau`
2. If blocks actions: set `blocksActions` table
3. Apply via `StatusEffectsService.apply(targetId, effectId, sourceId, params)`

### Debugging Tips

- **Hitbox visualization**: Set `DEBUG_VIS = true` in skill files
- **Network stats**: Call `dispatcher:dumpStats()`
- **Skill gating**: Add prints in `SkillsManager.useSkill`
- **Combo timing**: Inspect `SessionManager.getActive(casterId)` for combo windows

