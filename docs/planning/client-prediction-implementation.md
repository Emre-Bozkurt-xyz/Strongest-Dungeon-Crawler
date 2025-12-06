# Client-Side Skill Prediction Implementation Plan

**Status**: In Progress  
**Started**: November 2, 2025  
**Goal**: Implement optimistic client-side skill prediction with proper state mirroring to eliminate input lag while maintaining server authority.

---

## 🎯 Core Principles

1. **"Never predict what you can mirror"** - Client maintains synced state from server (cooldowns, resources, locks)
2. **Server is authoritative** - All damage, costs, and validation happen server-side
3. **BaseSkill handles complexity** - Keep skill implementations (Punch, TripleStrike) simple and focused on logic
4. **Graceful degradation** - Rare desync cases handled elegantly without disrupting gameplay

---

## 📋 Implementation Phases

### ✅ Phase 0: Foundation (COMPLETED)

**Files Created**:
- `src/shared/skills/SkillTimingResolver.luau` - Shared timing calculation logic
- `src/client/SkillsFramework/ComboStateClient.luau` - Client-side combo state tracker

**Files Modified**:
- `src/server/SkillsFramework/SkillTimingService.luau` - Refactored to use shared resolver
- `src/shared/skills/ClientSpec.luau` - Added timing metadata (tags, stepDurations)

**Result**: Client can predict timing using same formula as server via cached stats.

---

### 🔄 Phase 1: State Mirroring & Gating (IN PROGRESS)

**Objective**: Client checks local state before actions to prevent awkward rollbacks.

#### 1.1 Client-Side State Tracking ✅ (Already Exists)

**Existing Systems**:
- `CooldownClient.luau` - Already mirrors cooldowns from server
  - `isOnCooldown(key)` - Check if skill on cooldown
  - `getRemaining(key)` - Get remaining cooldown time
  - Receives `CooldownEvents` from server (`cd_start`, `cd_clear`)

**Verification Needed**:
- [ ] Confirm server emits cooldown events for:
  - Per-skill cooldowns
  - Global Cooldown (GCD) with key `__GCD__`
- [ ] Confirm `CooldownClient` correctly caches and updates state

---

#### 1.2 Resource Mirroring ✅ (COMPLETED)

**Current State**:
- `StatsClient.luau` - Already mirrors stats via deltas ✅
- Pools (Health, Mana, Stamina) included in stats ✅

**Implementation**:
```lua
-- StatsClient now provides:
function StatsClient.getPoolCurrent(poolType: string): number?
function StatsClient.getPoolMax(poolType: string): number?
function StatsClient.getStatValue(statType: string): number?

-- Usage:
local currentMana = StatsClient.getPoolCurrent("Mana")
local maxStamina = StatsClient.getPoolMax("Stamina")
local attackSpeed = StatsClient.getStatValue("AttackSpeed")
```

**Tasks**:
- [x] Add helper to `StatsClient` for easy pool queries
- [x] Add helper to `StatsClient` for static stat queries
- [x] No new mirroring needed - already synced via `StatsDelta` events

---

## ✅ Phase 1.3: Execution Lock Mirroring (COMPLETED)

**Implementation**:
```lua
-- src/client/SkillsFramework/ExecutionClient.luau (CREATED)
local executionState = {
    isLocked = false,
    lockedSkill = nil,
}

function ExecutionClient.setLocked(skillName: string?)
function ExecutionClient.isLocked(): boolean
function ExecutionClient.getLockedSkill(): string?
```

**Server Changes**:
```lua
-- Server: ExecutionService (MODIFIED)
-- Emit events on lock state changes
dispatcher:emit("ExecutionStateUpdate", {
    locked = true,
    skillName = "Punch",
}, { targets = player })
```

**Tasks**:
- [x] Create `ExecutionClient.luau`
- [x] Server: Add event emission to `ExecutionService.begin()`
- [x] Server: Add event emission to `ExecutionService.complete()`
- [x] Server: Add event emission to `autoFinish()`
- [x] Client: Listen to `ExecutionStateUpdate` events

---

## ✅ Phase 1.4: Server Metadata Emission (COMPLETED)

**Objective**: Server calculates skill costs using full observer/mediator pipeline and sends hints to clients.

**Implementation**:
```lua
-- src/server/SkillsFramework/SkillMetadataService.luau (CREATED)
function SkillMetadataService.updateSkill(player: Player, skillName: string)
function SkillMetadataService.updateAllSkills(player: Player)
-- Calculates costs with StatsManager.resolvePoolCost (full observer pipeline)
-- Emits SkillMetadataUpdate events on Skills channel
-- Handles SkillMetadataSnapshot requests for initial sync
```

**Client Integration**:
```lua
-- src/client/SkillsFramework/SkillMetadataClient.luau (ENHANCED)
-- Now fully extensible with:
-- - getCost(skillName, step?) - handles combo per-step costs
-- - getCostResource(skillName)
-- - getEstimatedDamage(skillName)
-- - getDamageBreakdown(skillName)
-- - requestSnapshot() - initial sync
```

**Server Integration**:
- Added to `init.server.luau`: Sends initial metadata 0.5s after stats initialization
- Hooked into `AttributesManager`: Updates all skills after attribute point spending
- Uses existing Skills network channel (no new channels needed)

**Tasks**:
- [x] Create `SkillMetadataService.luau` with cost calculation logic
- [x] Use `StatsManager.resolvePoolCost` for observer-modified costs
- [x] Implement `SkillMetadataSnapshot` request handler
- [x] Integrate into server initialization
- [x] Hook into `AttributesManager.spendAttributePoint` for updates
- [x] Support combo per-step costs via `comboCosts` array

**Future Extensions**:
- TODO: Add damage estimates when damage calculation system is ready
- TODO: Hook into equipment changes to update metadata
- TODO: Hook into status effect application/removal

---

## ✅ Phase 1.5: BaseSkill Gating Methods (COMPLETED)

**Objective**: Centralize all pre-flight checks in `BaseSkill` so skills validate BEFORE starting animations.

**Implementation**:
```lua
-- src/client/SkillsFramework/Skills/BaseSkill.luau (MODIFIED)

-- Export type for rejection reasons
export type RejectionReason = 
	"on_cooldown" | "on_gcd" | "locked" | 
	"insufficient_resources" | "invalid_combo_window" | "unknown"

-- Pre-flight validation using local cached state
function BaseSkill:canUseLocally(comboStep: number?): (boolean, RejectionReason?)
    -- Check execution lock (allows same skill for combo chaining)
    if ExecutionClient.isLocked() then
        local lockedSkill = ExecutionClient.getLockedSkill()
        if lockedSkill ~= self.name then
            return false, "locked"
        end
    end
    
    -- Check cooldown
    if CooldownClient.getRemaining(self.name) > 0 then
        return false, "on_cooldown"
    end
    
    -- Check GCD
    if CooldownClient.getRemaining("__gcd") > 0 then
        return false, "on_gcd"
    end
    
    -- Check resources using SkillMetadataClient
    local hasResources, _costInfo = self:checkResourcesLocal(comboStep)
    if not hasResources then
        return false, "insufficient_resources"
    end
    
    return true, nil
end

-- Check resources using server-computed costs from SkillMetadataClient
function BaseSkill:checkResourcesLocal(comboStep: number?): (boolean, table?)
    local cost = SkillMetadataClient.getCost(self.name, comboStep)
    local resource = SkillMetadataClient.getCostResource(self.name)
    
    -- Graceful degradation if metadata not cached yet
    if not cost or not resource or cost <= 0 then
        return true, nil
    end
    
    -- Check pool current vs cost
    local currentPool = StatsClient.getPoolCurrent(resource)
    if not currentPool then
        return true, { cost = cost, resource = resource } -- Defensive
    end
    
    return currentPool >= cost, { cost = cost, resource = resource }
end

-- Show visual/audio feedback for rejection
function BaseSkill:showRejectionFeedback(reason: RejectionReason)
    warn("Skill rejected locally:", self.name, "Reason:", reason)
    -- TODO: Implement UI feedback (flash red, play error sound, floating text)
end
```

**Updated Skill Implementations**:
```lua
-- src/client/SkillsFramework/Skills/BasicSkill.luau (MODIFIED)
function BasicSkill:use()
    -- PRE-FLIGHT CHECK: Validate local state BEFORE starting animation
    local canUse, rejectionReason = self:canUseLocally()
    if not canUse then
        self:showRejectionFeedback(rejectionReason)
        return -- Animation never starts - no rollback needed!
    end
    
    -- Predict timing and play animation immediately...
end

-- src/client/SkillsFramework/Skills/BasicComboSkill.luau (MODIFIED)
function BasicComboSkill:use()
    -- Predict combo step...
    local predictedStep = ComboStateClient.predictNextStep(self.name, totalSteps, windowDuration)
    
    -- PRE-FLIGHT CHECK with combo step for accurate cost
    local canUse, rejectionReason = self:canUseLocally(predictedStep)
    if not canUse then
        self:showRejectionFeedback(rejectionReason)
        if rejectionReason ~= "invalid_combo_window" then
            ComboStateClient.clear(self.name)
        end
        return
    end
    
    -- Play animation immediately...
end
```

**Tasks**:
- [x] Add `canUseLocally()` to `BaseSkill`
- [x] Add `checkResourcesLocal()` to `BaseSkill` using `SkillMetadataClient`
- [x] Add `showRejectionFeedback()` to `BaseSkill`
- [x] Update `BasicSkill:use()` to gate before animation
- [x] Update `BasicComboSkill:use()` to gate before animation with combo step
- [x] Remove deprecated `onServerRejected()` rollback logic
- [x] Simplify server rejection handling (rare edge cases only)

**Benefits Achieved**:
- ✅ **Zero input lag**: Animations start instantly after local validation
- ✅ **No rollback needed**: Animations never start if validation fails
- ✅ **Clean architecture**: Gating logic centralized in `BaseSkill`
- ✅ **Accurate costs**: Uses server-computed metadata with full observer pipeline
- ✅ **Graceful degradation**: Works even if metadata not cached yet

---

## ✅ Phase 1.6: Prediction Helpers & Async Callbacks (COMPLETED)

**Objective**: Add reusable prediction helpers to `BaseSkill` and refactor networking to use clean callbacks.

**Implementation**:
```lua
-- src/client/SkillsFramework/Skills/BaseSkill.luau (ADDED)

-- Predict timing locally using client's cached stats
function BaseSkill:predictTiming(): (number, number?)
    -- Uses SkillTimingResolver with StatsClient lookup
    -- Returns: tempo, durationScale
end

-- Calculate predicted duration for animation
function BaseSkill:predictDuration(): number?
    -- Uses baseDuration from config and predictTiming()
    -- Returns: predictedDuration or nil
end

-- Request skill use with callbacks (non-blocking)
function BaseSkill:requestUseAsync(
    onConfirm: ((data: any) -> ())?,
    onReject: ((reason: string) -> ())?
)
    -- Spawns async request, calls appropriate callback
end
```

**Updated Implementations**:
```lua
-- BasicSkill.luau - Simplified to use helpers
function BasicSkill:use()
    -- Gate check...
    
    local predictedDuration = self:predictDuration()
    self:playAnimation(animSpec, { duration = predictedDuration })
    
    self:requestUseAsync(
        function(data)
            -- Reconcile timing
        end,
        function(reason)
            warn("Server rejected:", reason)
        end
    )
end

-- BasicComboSkill.luau - Combo-specific duration prediction
function BasicComboSkill:use()
    -- Gate check with predictedStep...
    
    -- Calculate duration for THIS combo step
    local predictedDuration: number? = nil
    if self.config.combo.stepDurations then
        local baseDuration = self.config.combo.stepDurations[predictedStep]
        if baseDuration then
            local _tempo, durationScale = self:predictTiming()
            if durationScale then
                predictedDuration = baseDuration * durationScale
            end
        end
    end
    
    self:playAnimation(animKey, { duration = predictedDuration, step = predictedStep })
    
    self:requestUseAsync(
        function(data)
            ComboStateClient.reconcile(...)
        end,
        function(reason)
            ComboStateClient.clear(self.name)
        end
    )
end
```

**Tasks**:
- [x] Add `predictTiming()` to BaseSkill
- [x] Add `predictDuration()` to BaseSkill
- [x] Add `requestUseAsync()` to BaseSkill with callbacks
- [x] Refactor `BasicSkill` to use prediction helpers
- [x] Refactor `BasicComboSkill` to use callbacks (keep combo duration logic)
- [x] Remove duplicate timing prediction code
- [x] Clean up imports (removed unused SkillTimingResolver, StatsClient from skills)

**Benefits Achieved**:
- ✅ **Reduced duplication**: Timing prediction logic in one place
- ✅ **Cleaner async**: Callbacks instead of inline `task.spawn`
- ✅ **Separation of concerns**: Combo-specific logic stays in BasicComboSkill
- ✅ **Type safety**: Proper callback signatures
- ✅ **Maintainability**: Easier to extend prediction logic

---

## Phase 2: Visual Feedback System (TODO)
        return
    end
    
    -- PREDICT: Timing calculation (abstracted to BaseSkill)
    local predictedDuration = self:predictDuration()
    
    -- EXECUTE: Skill-specific animation logic
    local animSpec = self.config.anim and self.config.anim.start
    local track = self:playAnimation(animSpec, {
        duration = predictedDuration,
    })
    
    -- REQUEST: Server validation (handled by BaseSkill)
    self:requestUseAsync(function(response)
        if not response.success then
            self:handleRejection(response.error, track)
        else
            self:handleConfirmation(response.data)
        end
    end)
end
```

**New BaseSkill Methods**:
```lua
-- Predict duration using client stats
function BaseSkill:predictDuration(baseDuration: number?): number?

-- Handle server rejection (fade out animation)
function BaseSkill:handleRejection(reason: string, track: AnimationTrack?)

-- Handle server confirmation (reconcile timing)
function BaseSkill:handleConfirmation(serverData: any)
```

**Tasks**:
- [ ] Add `predictDuration()` to `BaseSkill`
- [ ] Add `handleRejection()` to `BaseSkill` (absorb from `onServerRejected`)
- [ ] Add `handleConfirmation()` to `BaseSkill` (timing reconciliation)
- [ ] Refactor `BasicSkill:use()` to use new abstracted methods
- [ ] Refactor `BasicComboSkill:use()` to use new abstracted methods

---

#### 1.6 Combo-Specific Abstractions (TODO)

**Objective**: Combo prediction logic in `BaseSkill` so `BasicComboSkill` stays simple.

**New BaseSkill Methods**:
```lua
-- Predict next combo step
function BaseSkill:predictComboStep(): number

-- Reconcile combo state with server
function BaseSkill:reconcileComboStep(serverStep: number, windowDuration: number)

-- Check if combo can advance
function BaseSkill:canAdvanceCombo(): boolean
```

**Simplified BasicComboSkill**:
```lua
function BasicComboSkill:use()
    local canUse, reason = self:canUseLocally()
    if not canUse then
        self:showRejectionFeedback(reason)
        return
    end
    
    -- BaseSkill handles combo prediction
    local predictedStep = self:predictComboStep()
    local predictedDuration = self:predictDuration(self.config.combo.stepDurations[predictedStep])
    
    -- Get animation for this step
    local animKey = self.config.anim.comboSteps[predictedStep].key
    
    local track = self:playAnimation(animKey, {
        duration = predictedDuration,
        step = predictedStep,
    })
    
    self:requestUseAsync(function(response)
        if not response.success then
            self:handleRejection(response.error, track)
            ComboStateClient.clear(self.name)
        else
            self:reconcileComboStep(response.data.step, response.data.window)
            self:handleConfirmation(response.data)
        end
    end)
end
```

**Tasks**:
- [ ] Add `predictComboStep()` to `BaseSkill` (wraps `ComboStateClient`)
- [ ] Add `reconcileComboStep()` to `BaseSkill` (wraps `ComboStateClient.reconcile`)
- [ ] Add `canAdvanceCombo()` to `BaseSkill`
- [ ] Refactor `BasicComboSkill:use()` to use abstracted methods

---

### 🎨 Phase 2: Visual Feedback (TODO)

**Objective**: Provide immediate UI/audio feedback for rejections without gameplay disruption.

#### 2.1 Cooldown Overlay Flash (TODO)

**Integration Point**: `SkillSlotUI.luau`

```lua
function SkillSlotUI.flashError(slotIndex: number, reason: string)
    local container = containerMap[slotIndex]
    if not container then return end
    
    local overlay = container:FindFirstChild("Overlay")
    if overlay then
        -- Flash red briefly
        local original = overlay.BackgroundColor3
        overlay.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
        task.delay(0.15, function()
            overlay.BackgroundColor3 = original
        end)
    end
end
```

**BaseSkill Integration**:
```lua
function BaseSkill:showRejectionFeedback(reason: string)
    -- Find slot this skill is in
    local slotIndex = self:findSlotIndex()
    if slotIndex then
        local SkillSlotUI = require(...)
        SkillSlotUI.flashError(slotIndex, reason)
    end
    
    -- Play sound
    if reason == "on_cooldown" then
        SoundService.play("UI_Click_Disabled")
    elseif reason == "insufficient_resources" then
        SoundService.play("UI_Empty")
    end
end
```

**Tasks**:
- [ ] Add `flashError()` to `SkillSlotUI`
- [ ] Add `findSlotIndex()` helper to `BaseSkill`
- [ ] Create sound effect assets or use placeholders
- [ ] Integrate feedback into `showRejectionFeedback()`

---

#### 2.2 Visual Hit Feedback (FUTURE)

**Objective**: Client-side visual hitbox queries (no damage) for instant hit markers/FX.

**Scope**: Phase 3+ - Not critical for initial rollout.

---

### 🧪 Phase 3: Testing & Validation (TODO)

**Objective**: Verify all systems work correctly under various conditions.

#### 3.1 Unit Tests

- [ ] `SkillTimingResolver` - Verify tempo calculations match server
- [ ] `ComboStateClient` - Verify step prediction and window expiry
- [ ] `CooldownClient` - Verify cooldown tracking and expiry
- [ ] `ExecutionClient` - Verify lock state tracking

#### 3.2 Integration Tests

- [ ] Spam skill during cooldown → No animation, flash feedback
- [ ] Use skill with insufficient resources → No animation, flash feedback
- [ ] Use skill during GCD → No animation, flash feedback
- [ ] Use skill during execution lock → Blocked (unless same skill combo)
- [ ] Combo chaining → Smooth step transitions without server wait
- [ ] High ping (simulate) → Animations play immediately, rare mismatches logged

#### 3.3 Edge Cases

- [ ] Stats not loaded yet → Fallback to default tempo, no crash
- [ ] Cooldown desync (client thinks ready, server says no) → Graceful rejection
- [ ] Combo window desync → Server corrects step, no rollback
- [ ] Resource desync → Server corrects pool value, syncs to client

---

## 📊 Success Metrics

**Perceived Input Lag**:
- Before: 50-200ms (ping-dependent)
- Target: <10ms (instant animation start)

**Rollback Rate**:
- Target: <1% of skill uses
- Acceptable: <5% on high ping (>200ms)

**Timing Accuracy**:
- Target: ±10ms between predicted and server duration
- Acceptable: ±50ms (logged, no rollback)

**User Experience**:
- ✅ Skills feel instant and responsive
- ✅ No jarring animation cancellations
- ✅ Clear feedback on why skills can't be used
- ✅ Server authority maintained (no cheating)

---

## 🗂️ File Structure Summary

### New Files (Created)
```
src/shared/skills/
  SkillTimingResolver.luau ✅

src/client/SkillsFramework/
  ComboStateClient.luau ✅
  ExecutionClient.luau ⏳ (TODO)
```

### Modified Files
```
src/server/SkillsFramework/
  SkillTimingService.luau ✅
  ExecutionService.luau ⏳ (add event emission)

src/client/
  StatsClient.luau ⏳ (add pool helpers)

src/client/SkillsFramework/
  SkillSlotUI.luau ⏳ (add flashError)

src/client/SkillsFramework/Skills/
  BaseSkill.luau ⏳ (add gating, prediction, reconciliation)
  BasicSkill.luau ⏳ (refactor to use BaseSkill abstractions)
  BasicComboSkill.luau ⏳ (refactor to use BaseSkill abstractions)

src/shared/skills/
  ClientSpec.luau ✅ (added timing metadata)
```

---

## 🚦 Current Status

### Completed ✅
- Shared timing resolver (`SkillTimingResolver`)
- Combo state prediction (`ComboStateClient`)
- Server timing service refactored
- Client spec timing metadata

### In Progress 🔄
- Phase 1.4: BaseSkill gating abstraction
- Phase 1.5: Skill implementation simplification

### Blocked ⛔
- None

### Next Steps 🎯
1. Add `StatsClient.getPoolCurrent()` helper
2. Create `ExecutionClient.luau`
3. Refactor `BaseSkill` to add gating methods
4. Simplify `BasicSkill` and `BasicComboSkill`
5. Add visual feedback to `SkillSlotUI`

---

## 📝 Design Decisions Log

### Decision 1: Where to place gating logic?
**Options**: 
- A) Each skill checks state
- B) BaseSkill checks state

**Chosen**: B (BaseSkill)  
**Rationale**: Keeps skill implementations focused on gameplay logic, easier to maintain, consistent behavior across all skills.

### Decision 2: Blocking vs non-blocking server requests?
**Options**:
- A) Block and wait for response
- B) Fire-and-forget async

**Chosen**: B (Async with callback)  
**Rationale**: Enables instant animation start, matches industry standard optimistic prediction, better UX on high ping.

### Decision 3: Roll back animations on mismatch?
**Options**:
- A) Always roll back
- B) Only roll back on rejection, not timing mismatch

**Chosen**: B  
**Rationale**: Timing mismatches (<50ms) are acceptable desync, full rollback only on critical failures (cooldown, resources). Matches user preference for "slight desync OK".

### Decision 4: Client-side hit detection?
**Options**:
- A) Implement now
- B) Defer to Phase 3+

**Chosen**: B (Future)  
**Rationale**: Server hitboxes work fine, client hits are nice-to-have for "juice" but not critical for responsive feel. Priority is input lag elimination.

---

## 🔗 Related Documentation

- [Skills Overview](../skills/overview.md) - Server/client skill architecture
- [Skills Timing](../skills/timing.md) - Combo controller and tempo resolver
- [Stats Overview](../stats/overview.md) - Stats system and client mirroring
- [Networking Overview](../networking/overview.md) - Dispatcher usage and channels

---

## 📅 Timeline Estimate

- **Phase 1.4-1.6** (BaseSkill abstraction): 2-3 hours
- **Phase 2** (Visual feedback): 1-2 hours
- **Phase 3** (Testing): 2-4 hours

**Total**: 5-9 hours of development time

---

**Last Updated**: November 2, 2025  
**Next Review**: After Phase 1 completion
