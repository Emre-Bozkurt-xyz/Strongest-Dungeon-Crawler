# AI Coding Agent Instructions

These project-specific instructions help an AI assistant work effectively in this Roblox (Luau) codebase.
Keep responses concise, reference concrete files, and follow the established execution / cooldown architecture.

## 1. High-Level Architecture
- **Skill Framework (server)**: Lives under `src/server/SkillsFramework/`.
  - `SkillsManager.luau`: Entry point for processing skill use requests (dispatcher request `SkillsRequest`). Handles gating: cooldowns, execution lock, and combo chaining.
  - `ExecutionService.luau`: Provides an execution lock per player+skill; supports optional auto-complete via duration and allows chaining the same combo skill.
  - `CooldownService.luau`: Authoritative per-skill cooldown + global cooldown (GCD) management; uses `os.clock()` style monotonic time.
  - `ComboService.luau`: Tracks combo progression (step, expiry window, per-step delays) and issues tokens to validate presses.
  - `SkillsConfig.luau`: Declarative definitions for skills (cooldown, gcd, combo metadata, per-hit timelines for non-combo skills).
  - `HitboxService.luau`: Cone/box spatial queries with optional debug visualization.
  - `ProjectileService.luau`: Projectile spawning and lifecycle management.
  - `Timeline.luau`: Generic scheduling system for timed sequences.
  - Individual skills in `Skills/` (`BaseSkill.luau`, `BaseComboSkill.luau`, `Punch.luau`, `TripleStrike.luau`): Encapsulate skill-specific logic and hit application.

- **Stats System (server/shared)**: Character progression and derived values.
  - `StatsManager.luau`: Server-authoritative stat management with dispatcher sync to clients. Handles base values, modifiers, pools (Health/Mana/Stamina).
  - `AttributesManager.luau`: RPG-style attributes (Strength, Agility, etc.) with point allocation and modifier system.
  - `StatClass.luau`, `PoolClass.luau`, `AttributeClass.luau`: Core stat computation with modifier chains.
  - `CombatService.luau`: Damage application using stat-derived values.
  - `RegenerationService.luau`: Pool regeneration over time.

- **Status Effects System**: `StatusEffectsService.luau` handles timed buffs/debuffs with complex stacking modes ("aggregate", "multi", "charges"), duration policies, and tick behaviors.

- **Input System (client)**: `InputManager.luau` provides action-based input binding with context switching. `ActionConfig.luau` defines key mappings.

- **Client FX/UI**: 
  - `FXPlayer.luau`: Asset-based particle/sound effects with pooling and automatic cleanup.
  - `SkillsClient.luau`: Receives skill events and coordinates animations/FX via `ClientSpec.luau` definitions.
  - UI controllers for health/mana bars, skill slots with cooldown overlays.
  - `AnimationPlayer.luau`: Animation state management and marker-driven FX triggers.

## 2. Core Runtime Concepts
- **Execution Phase vs Cooldown**: Cooldown **starts only after execution completes** (see `ExecutionService.onCompleted` listener in `SkillsManager`). Never start cooldown inside an individual skill now.
- **Execution Lock**: While executing, other skills are blocked. Combo chaining of the SAME skill is allowed (flag passed in `beginExecution(nil, true)` for combos). Non-combo skills cannot re-enter while locked (anti-spam logic in `SkillsManager.useSkill`).
- **Combos**: Steps advance through `ComboService.nextStep(...)`, which enforces: window timeout, per-step minimum delay (`stepDelays`), and token sequencing.
- **Hit Timing**: Combo skills optionally delay damage via `combo.hitDelays[step]`. Non-combo timeline skills (e.g. `TripleStrike`) use a `hits` array of `{ t, yaw, coneAngle, coneRange, damageMult }` and schedule each impact.
- **Recovery**: Optional `combo.recovery` extends execution AFTER the final hit before cooldown/GCD start (implemented in `BaseComboSkill`).

## 3. Key Patterns & Conventions
- Use `os.clock()` (monotonic) for timing logic (Cooldown / Combo services). Avoid `tick()`.
- Skill files: Constructed via `SkillsConfig.addSkill`, which requires a module named identically under `Skills/`.
- Emitted event phases (client consumers rely on these string keys): `start`, `step`, `fx`, `combo_wait` (`open=true/false`), `end`.
- For new combo skills: inherit from `BaseComboSkill`, implement `onComboStep(step, requestData)`; DO NOT start cooldown manually.
- For timeline (multi-hit) single skills: inherit `BaseSkill`, compute total duration (last hit time + tail), call `beginExecution(totalDuration, false)`, schedule hits, and call or schedule `completeExecution()` if no duration auto-complete.
- Always defer completion until after final impact logic. If impact delay is zero, use `task.defer` before `completeExecution()` (see current `BaseComboSkill` logic).
- Prevent spam: rely on `ExecutionService.isLocked` + gating in `SkillsManager` not ad-hoc checks in each skill.
- **Stats/Attributes**: Use `StatsManager.setBaseStat()` and `AttributesManager.addModifier()` for server changes. Client receives deltas via dispatcher events.
- **Status Effects**: Register effects in `StatusEffects/EffectsIndex.luau` with stacking modes. Apply via `StatusEffectsService.apply(target, effectId, params)`.
- **Input Handling**: Define actions in `ActionConfig.luau`, bind callbacks via `InputManager.on(actionName, callback)`.
- **Client FX**: Use `FXPlayer.playAt(key, cframe)` for positioned effects. Animation markers drive FX via `ClientSpec` definitions.
- **UI Controllers**: Follow pattern of listening to dispatcher events and updating UI elements (see `HealthBarController`, `SkillSlotUI`).

## 4. Adding a New Skill (Example)
1. Define entry in `SkillsConfig.skills`:
```lua
NewSkill = {
  name = "NewSkill", cooldown = 5, gcd = 1, level = 1,
  hits = { { t = 0.2, yaw = 0, coneAngle = 40, coneRange = 7, damageMult = 1.1 } },
}
```
2. Create `src/server/SkillsFramework/Skills/NewSkill.luau`:
```lua
local BaseSkill = require(script.Parent.BaseSkill)
local CombatService = require(script.Parent.Parent.Parent.CombatService)
local HitboxService = require(script.Parent.Parent.HitboxService)

local NewSkill = {}
NewSkill.__index = NewSkill
setmetatable(NewSkill, { __index = BaseSkill })

function NewSkill.new(player, data)
  local self = BaseSkill.new(player, data)
  setmetatable(self, NewSkill)
  return self
end

function NewSkill:use()
  local hits = (self.config and self.config.hits)
  local tail = 0.05
  local total = (hits and hits[1] and hits[1].t or 0) + tail
  self:beginExecution(total, false)
  for i, h in ipairs(hits) do
    task.delay(h.t, function()
      self:emitStep(i)
      -- hitbox + damage logic here
    end)
  end
  task.delay(total, function() self:completeExecution() end)
end

return NewSkill
```
3. No manual cooldown logic—handled on execution completion.

## 5. Common Pitfalls (Avoid These)
- Starting cooldowns directly in skill modules (breaks unified lifecycle).
- Forgetting `allowChain` true for combos -> subsequent steps blocked.
- Using a planned duration for a combo (can auto-complete before final step).
- Skipping `task.defer` when final hit delay is zero (risk completion before damage logic).
- Re-implementing spam gating inside individual skills instead of central `SkillsManager`.

## 6. Execution / Combo Timing Reference
- Combo advance allowed only if: within `window` AND after `stepDelays[currentStep]` has elapsed.
- Final combo completion delay = `hitDelays[lastStep] + recovery` (if present) before `completeExecution()`.
- Global Cooldown (GCD) & per-skill cooldown both start from `ExecutionService.onCompleted` callback.

## 7. Testing / Debug Aids
- Add temporary prints in `BaseComboSkill:onComboStep` or `SkillsManager.useSkill` to trace step numbers if a combo stall occurs.
- For hitbox visualization set `DEBUG_VIS = true` in skills that support it (e.g., `TripleStrike`).
- Simulate fast spam to verify gating: attempt to reuse `TripleStrike` before completion; it should now ignore extra requests.

## 7.1 Dispatcher QoS and request tuning (Attributes spam)
- Symptoms: Rapid attribute button clicks can still queue up; keep dispatcher calls lightweight and reduce request bursts.
- Client-side fixes:
  - Keep `Attributes` channel set to `HIGH` QoS in `Networking/Channels.luau` and avoid batching client requests.
  - Coalesce rapid clicks per attribute client-side (e.g., 80ms window) and send a single request with `count` to reduce send volume.
- Server-side fixes:
  - Extend `AttributesSpendPoint` handler to accept `{ target: string, count?: number }` and loop spend up to `count` or available AP.
- Middleware / throttling (optional):
  - Wrap `dispatcher:onRequest` handlers to enforce per-player rate limits or guard against abuse; return early to block if limits exceeded.
- QoS guidance: Use `CRITICAL` sparingly (skills/cooldowns), prefer `HIGH` for interactive UI, and fall back to `NORMAL`/`BACKGROUND` for passive replication.

## 8. When Modifying Core Services
- Maintain event phase contract (`SkillsEvent`). Adding new phases? Document them here and update clients.
- Preserve monotonic time assumptions (`now()` helpers).
- Keep execution completion as the single point that triggers cooldown dispatch.

## 9. Safe Extension Points
- Add new damage types by extending `CombatService.applyDamage` signature (and adjusting consumers).
- Extend skill config with optional fields; gate their use with nil checks to avoid breaking existing skills.
- Add new status effects in `StatusEffects/EffectsIndex.luau` with appropriate stacking/ticking modes.
- Extend stats/attributes via config files and modifier system without breaking existing calculations.
- Add new input actions via `ActionConfig.luau` contexts and bind in client code.
- Create new FX assets and reference them in `ClientSpec.luau` for automatic coordination.

## 10. Development Workflow
- **Build**: Use `rojo build -o "Strongest Dungeon Crawler.rbxlx"` then `rojo serve` for live sync.
- **Debugging Skills**: Toggle `DEBUG_VIS = true` in skills for hitbox visualization. Add prints in `SkillsManager.useSkill` for gating traces.
- **Testing Combos**: Verify step advancement with different timing patterns. Check execution lock prevents spam clicks.
- **Client FX**: Animation markers in `ClientSpec` automatically trigger FX. Use `FXPlayer.playAt` for manual placement.

## 11. Glossary
- Execution: Active phase from `beginExecution` until `completeExecution`.
- Recovery: Optional post-impact lock still counted as execution time.
- GCD: Global Cooldown preventing any skill use while active (separate from execution lock).
- Combo Window: Time budget to press again to advance to next step.

---
If any section is unclear or you need deeper coverage (e.g., CooldownService internals, UI event consumption), request a follow‑up and specify the area.
