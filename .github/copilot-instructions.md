# AI Coding Agent Instructions

These project-specific instructions help an AI assistant work effectively in this Roblox (Luau) codebase.
Keep responses concise, reference concrete files, and follow the established execution / cooldown architecture.

## 1. High-Level Architecture
- **Skill Framework (server)**: Lives under `src/server/SkillsFramework/`.
  - `SkillsManager.luau`: Entry point for processing skill use requests (NetRay request `SkillsRequest`). Handles gating: cooldowns, execution lock, and combo chaining.
  - `ExecutionService.luau` (not shown here but present): Provides an execution lock per player+skill; supports optional auto-complete via duration and allows chaining the same combo skill.
  - `CooldownService.luau` (assumed present): Authoritative per-skill cooldown + global cooldown (GCD) management; uses `os.clock()` style monotonic time.
  - `ComboService.luau`: Tracks combo progression (step, expiry window, per-step delays) and issues tokens to validate presses.
  - `SkillsConfig.luau`: Declarative definitions for skills (cooldown, gcd, combo metadata, per-hit timelines for non-combo skills).
  - Individual skills in `Skills/` (`BaseSkill.luau`, `BaseComboSkill.luau`, `Punch.luau`, `TripleStrike.luau`): Encapsulate skill-specific logic and hit application.

- **Client Skill FX/UI (not fully shown)**: Receives events via `NetRay:RegisterEvent("SkillsEvent")`. `BaseSkill` emits phases: `start`, `step`, `fx`, `combo_wait`, `end`.

- **Stats / Combat**: `StatsManager` and `CombatService` provide stat-derived damage application. Hitbox queries performed via `HitboxService` (cone/box queries, optional debug visuals).

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
  local total = (hits and hits[#hits] and hits[#hits].t or 0) + tail
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

## 8. When Modifying Core Services
- Maintain event phase contract (`SkillsEvent`). Adding new phases? Document them here and update clients.
- Preserve monotonic time assumptions (`now()` helpers).
- Keep execution completion as the single point that triggers cooldown dispatch.

## 9. Safe Extension Points
- Add new damage types by extending `CombatService.applyDamage` signature (and adjusting consumers).
- Extend skill config with optional fields; gate their use with nil checks to avoid breaking existing skills.

## 10. Glossary
- Execution: Active phase from `beginExecution` until `completeExecution`.
- Recovery: Optional post-impact lock still counted as execution time.
- GCD: Global Cooldown preventing any skill use while active (separate from execution lock).
- Combo Window: Time budget to press again to advance to next step.

---
If any section is unclear or you need deeper coverage (e.g., CooldownService internals, UI event consumption), request a follow‑up and specify the area.
