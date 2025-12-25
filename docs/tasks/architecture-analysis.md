# Architecture Analysis & Hit Feedback Fix

**Created**: December 24, 2025  
**Status**: In Progress  
**Goal**: Fix hit feedback architecture to be client-driven (immediate) instead of server-driven (delayed)

---

## 🔍 Problem Summary

**What we built (WRONG):**
- HitFeedbackController waits for server `HitEvent` before showing:
  - White flash on hit target
  - Hit sounds
  - Hit reaction animations
  - Camera shake
- Server emits `SkillCastSound` event for cast sounds
- All feedback has network round-trip latency

**What user intended (CORRECT):**
- Client plays cast sound **immediately** when skill starts (no network)
- Client plays hit sound/flash **immediately** on animation marker ("Impact", "Punch_Land")
- Server `HitEvent` only used for:
  - Damage numbers (needs server-calculated damage)
  - Stagger confirmation (needs server authority)
- Zero latency for visual/audio feedback

---

## 📊 Current System Trace

### Client Skill Execution Flow (What Happens Now)

```
1. Player presses skill key
2. InputManager → SkillsClient.useSkill(skillName)
3. Client BasicSkill/BasicComboSkill:use()
   - canUseLocally() check (good - immediate gating)
   - playAnimation() - starts animation immediately (good)
     - Binds marker events for FX (good)
   - requestUseAsync() - sends to server
4. AnimationCoordinator plays animation
   - GetMarkerReachedSignal("Punch_Land") fires
   - FXPlayer.playAttached() triggers FX (good)
5. Server receives request, validates, executes skill
6. Server CombatService.applyDamage() → broadcastHit()
7. Server emits HitEvent with damage result
8. ❌ Client HitFeedbackController.onHit() receives HitEvent
   ❌ THEN plays flash, sound, hit animation (DELAYED!)
```

### What Should Happen

```
1. Player presses skill key
2. Client validates locally, plays animation immediately
3. Animation marker "Impact" or "Punch_Land" fires
4. ✅ Client IMMEDIATELY plays:
   - Hit flash (white highlight on target)
   - Hit sound
   - Small camera shake
5. Server calculates damage, sends HitEvent
6. Client receives HitEvent
   - Shows damage number (needs server value)
   - Server confirms stagger (if threshold met)
```

---

## 🛠️ What Already Exists (Underutilized)

### AnimationCoordinator (Working - Needs Hook)
Location: `src/client/Animation/AnimationCoordinator.luau`
```lua
-- This already works! We just need to use it for hit feedback
AnimationCoordinator.onSkillMarker(skillName, markerName, callback)
```

### ClientSpec.fx.markers (Already Configured)
Location: `src/shared/skills/ClientSpec.luau`
```lua
markers = {
    Punch_Land = "Punch_Land",  -- This is a HIT marker!
    punch_windup_start = { key = "Punch_Windup", action = "start" },
}
```

### BaseSkill:playAnimation() (Already Binds Markers)
Location: `src/client/SkillsFramework/Skills/BaseSkill.luau` lines 67-145
- Sets up marker handlers in `for markerName, val in pairs(markers)`
- It plays FX on markers - we just need to ADD hit feedback here

---

## 🚫 What We Added (Wrong Direction)

### 1. Server-side SkillCastSound (WRONG)
Location: `src/server/SkillsFramework/Skills/BaseSkill.luau` lines 118-151
```lua
function BaseSkill:playCastSound()
    -- Emits SkillCastSound event from server
    dispatcher:emit("SkillCastSound", {...})
end
```
**Problem:** Client waits for network before playing sound  
**Fix:** Client plays sound immediately in skill:use()

### 2. HitFeedbackController Listening to HitEvent (WRONG)
Location: `src/client/ui/HitFeedbackController.luau` lines 256-260
```lua
dispatcher:on("HitEvent", function(hitEvent)
    HitFeedbackController.onHit(hitEvent) -- Flash, sound, etc.
end)
```
**Problem:** Waits for server round-trip  
**Fix:** Use animation markers for immediate feedback

### 3. SkillCastSound Event Handler (WRONG)
Location: `src/client/ui/HitFeedbackController.luau` lines 223-248
```lua
dispatcher:on("SkillCastSound", onCastSound)
```
**Problem:** Server tells client to play sound  
**Fix:** Client plays sound immediately when animation starts

---

## ✅ Correct Changes We Made (Keep These)

1. **ActionPermissions System** - Query layer for permission checks ✓
2. **Blocking Status Effects** - Stagger, Stun, Root, Silence in StatusEffectsService ✓
3. **Character Specs System** - CharacterSpec types, Registry, specs ✓
4. **StaggerSystem (Server-Side)** - Listens to HitEvent, applies stagger ✓
5. **StaggerCalculator** - Dynamic threshold scaling ✓

These are all correct because they're server-authoritative decisions, not UX feedback.

---

## 📋 Fix Plan

### Task 1: Client-Side Cast Sounds (EASY - START HERE)
**Files:** 
- `src/client/SkillsFramework/Skills/BasicSkill.luau`
- `src/client/SkillsFramework/Skills/BasicComboSkill.luau`
- `src/client/SkillsFramework/Skills/BaseSkill.luau`

Add method to BaseSkill and call immediately in use():
```lua
-- BaseSkill.luau (CLIENT)
function BaseSkill:playCastSoundLocal()
    local castSounds = self.config and self.config.castSounds
    if not castSounds or #castSounds == 0 then return end
    local soundId = castSounds[math.random(1, #castSounds)]
    -- Play immediately at character position
    SoundService.playAtPosition(soundId, self.player.Character.HumanoidRootPart.Position)
end

-- BasicSkill.luau - in use() after validation
self:playCastSoundLocal() -- NEW: Play immediately, no network
self:playAnimation(...)
```

### Task 2: Client-Side Hit Feedback via Markers (MAIN FIX)
**File:** `src/client/SkillsFramework/Skills/BaseSkill.luau`

Modify playAnimation() marker binding to detect hit markers:
```lua
-- In the marker binding loop, check if this is a hit marker
local isHitMarker = markerName == "Impact" 
    or markerName:match("_Land$") 
    or markerName:match("_Hit$")
    or (type(val) == "table" and val.isHitMarker)

if isHitMarker then
    -- Register for hit feedback in addition to FX
    self.markerEventListenerDestroyers[markerName .. "_hitfeedback"] = 
        self:bindMarkerEvent(markerName, function(_ctx)
            HitFeedback.playImmediateHitFeedback(self.player)
        end)
end
```

### Task 3: Refactor HitFeedbackController  
**File:** `src/client/ui/HitFeedbackController.luau`

Split responsibilities:
```lua
-- KEEP for damage numbers (needs server value):
dispatcher:on("HitEvent", function(event)
    -- Show damage number only
    DamageNumberController.show(event.targetId, event.result.totalDamage)
end)

-- ADD for immediate marker-driven feedback:
function HitFeedbackController.playImmediateFeedback(player)
    -- Play hit sound locally
    -- Camera shake
    -- (Flash requires target - see open questions)
end

-- REMOVE SkillCastSound listener (no longer needed)
```

### Task 4: Clean Up Server-Side Sound Emission
**File:** `src/server/SkillsFramework/Skills/BaseSkill.luau`

Options:
- A) Remove `playCastSound()` entirely
- B) Keep for OTHER players watching (replicate sounds to non-local players)
- C) Move sound replication to Replicator.emitFX system

### Task 5: Update ClientSpec with Hit Markers
**File:** `src/shared/skills/ClientSpec.luau`

Add `isHitMarker = true` flag to impact markers:
```lua
markers = {
    Punch_Land = { key = "Punch_Land", isHitMarker = true },
    Impact = { isHitMarker = true },
}
```

---

## 🔢 Priority Order

```markdown
- [x] Task 1: Client Cast Sounds - Added playCastSoundLocal() to BaseSkill, called in BasicSkill/BasicComboSkill
- [x] Task 3: Refactor HitFeedbackController - Now only handles server-authoritative feedback (damage numbers, crit flash, stagger)
- [x] Task 2: Marker Hit Feedback - Added ImmediateHitFeedback + ClientHitDetection modules, hooked into BaseSkill marker events
- [x] Task 5: Update ClientSpec - Added isHitMarker flag, hitSounds, castSounds, hitConeAngle/Range to Punch config
- [x] Task 4: Clean Server Sounds - Deprecated server-side playCastSound(), removed SkillCastSound from Combat channel
```

## ✅ Implementation Complete

### New Files Created:
- `src/client/fx/ClientHitDetection.luau` - Client-side spatial queries (cone, sphere, ray)
- `src/client/fx/ImmediateHitFeedback.luau` - Immediate feedback on markers (flash, sound, shake)

### Modified Files:
- `src/client/fx/Replicator.luau` - Added SFX support (emitSFX, playSoundAt, playSoundAttached)
- `src/client/SkillsFramework/Skills/BaseSkill.luau` - Added playCastSoundLocal(), hit marker detection in playAnimation()
- `src/client/SkillsFramework/Skills/BasicSkill.luau` - Calls playCastSoundLocal() after validation
- `src/client/SkillsFramework/Skills/BasicComboSkill.luau` - Calls playCastSoundLocal() after validation
- `src/client/ui/HitFeedbackController.luau` - Simplified to server-authoritative feedback only
- `src/shared/Networking/Channels.luau` - Added SFXEvent to FX channel, removed SkillCastSound from Combat
- `src/shared/skills/ClientSpec.luau` - Added isHitMarker, hitSounds, castSounds, cone settings
- `src/server/SkillsFramework/Skills/BaseSkill.luau` - Deprecated playCastSound()

---

## ❓ Open Questions (Need Your Input)

1. **Target Flash Timing:**
   - Should flash be immediate on marker (needs client-side target prediction)?
   - Or is flash OK to wait for HitEvent (only 50-100ms delay)?
   - Recommendation: Immediate for hit sound/shake, wait for HitEvent for flash

2. **Sound Replication:**
   - Do we need server to broadcast sounds to OTHER players?
   - Or can the existing Replicator.emitFX handle it?
   - Recommendation: Add sound support to Replicator

3. **Scope:**
   - Cast sounds: Always immediate ✓
   - Hit sounds: Immediate on marker ✓  
   - Camera shake: Immediate on marker ✓
   - Hit flash: Wait for HitEvent (needs target from server)

---

## 📝 Notes & Decisions

*Space for capturing decisions as we discuss*

---

## 📚 Related Documents

- [client-prediction-implementation.md](../planning/client-prediction-implementation.md) - Original prediction architecture
- [skills_evolution_plan.md](../skills_evolution_plan.md) - Phase 4: Animation Marker Integration
- [copilot-instructions.md](../../.github/copilot-instructions.md) - Core architecture guidelines

