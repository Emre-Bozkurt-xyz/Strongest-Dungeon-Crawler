# Combat System Architecture Migration Plan

This document outlines a phased migration from the current fragile execution/combo system to a robust, unified architecture. The goal is to achieve responsive client prediction while maintaining server authority, without the race conditions and state desync issues that plague the current implementation.

---

## 0. Problem Statement

### Current Architecture Issues

The current system has two separate state machines that must stay synchronized:

1. **ExecutionService** - Tracks "is player executing a skill?"
   - Token-based validation
   - Duration-based auto-completion via `task.delay()`
   - Manual completion via `completeExecution()`
   - Interrupt capability

2. **ComboService** - Tracks "what combo step is the player on?"
   - Window-based expiry via `task.delay()`
   - Step advancement with tokens
   - Busy/until timing gates

**The Problem:** These are logically ONE concept (a skill execution session) split into TWO services that must stay in sync. When they desync (due to network latency, callback races, or edge cases), the system enters inconsistent states that are difficult to recover from.

### Observed Symptoms

- Execution state "mysteriously disappears" before completion callbacks fire
- Client stays locked when server has no state to unlock
- Combo windows expire but execution cleanup doesn't happen
- Multiple `task.delay()` callbacks race against each other
- Self-healing timeouts mask bugs rather than fixing them

### Root Causes

1. **Callback-based timing** - `task.delay()` creates fire-and-forget futures that can't be cancelled or coordinated
2. **Implicit state coupling** - ExecutionService and ComboService don't share a formal contract
3. **Event-driven cleanup chains** - `complete() → onCompleted → listener → clear()` - any broken link breaks everything
4. **Partial client prediction** - Client predicts some state but can't properly reconcile when server disagrees

---

## 1. Target Architecture

### 1.1 Unified SkillSession Model

Replace ExecutionService + ComboService with a single **SkillSession** that owns ALL state:

```lua
export type SkillSession = {
    -- Identity
    id: string,              -- Unique session ID (for client correlation)
    skillId: string,         -- Which skill
    casterId: string,        -- Who is casting
    
    -- State Machine
    state: SessionState,     -- IDLE | CASTING | ACTIVE | RECOVERY | COMPLETED | CANCELLED
    stateEnteredAt: number,  -- os.clock() when current state began
    
    -- Combo (optional, nil for non-combo skills)
    combo: {
        currentStep: number,
        totalSteps: number,
        windowExpiresAt: number?,  -- When combo input window closes
        stepToken: number,         -- Sequencing token
    }?,
    
    -- Timing
    executionExpiresAt: number,   -- Hard deadline - session WILL end by this time
    recoveryEndsAt: number?,      -- When recovery period ends (if applicable)
    
    -- Metadata
    createdAt: number,
    lastActivity: number,         -- Updated on any state change
}

export type SessionState = "IDLE" | "CASTING" | "ACTIVE" | "RECOVERY" | "COMPLETED" | "CANCELLED"
```

### 1.2 Explicit State Machine

All state transitions go through a single `transition()` method that enforces legal transitions:

```lua
local LEGAL_TRANSITIONS = {
    IDLE = { "CASTING" },
    CASTING = { "ACTIVE", "CANCELLED" },
    ACTIVE = { "RECOVERY", "COMPLETED", "CANCELLED" },
    RECOVERY = { "COMPLETED", "CANCELLED" },
    COMPLETED = {},  -- Terminal
    CANCELLED = {},  -- Terminal
}

function SessionManager:transition(sessionId: string, newState: SessionState, reason: string?): boolean
    local session = self.sessions[sessionId]
    if not session then return false end
    
    local allowed = LEGAL_TRANSITIONS[session.state]
    if not table.find(allowed, newState) then
        warn(`Illegal transition: {session.state} → {newState} for {sessionId}`)
        return false
    end
    
    local now = os.clock()
    session.state = newState
    session.stateEnteredAt = now
    session.lastActivity = now
    
    -- Emit state change event to clients
    self:emitStateChange(session, newState, reason)
    
    -- Handle terminal states
    if newState == "COMPLETED" or newState == "CANCELLED" then
        self:scheduleCleanup(sessionId)
    end
    
    return true
end
```

### 1.3 Heartbeat-Based Expiry

Replace `task.delay()` callbacks with a heartbeat loop that checks all active sessions:

```lua
function SessionManager:startHeartbeat()
    self.heartbeatConnection = RunService.Heartbeat:Connect(function()
        local now = os.clock()
        
        for sessionId, session in self.sessions do
            -- Skip terminal states
            if session.state == "COMPLETED" or session.state == "CANCELLED" then
                continue
            end
            
            -- Hard timeout - session exceeded maximum lifetime
            if now >= session.executionExpiresAt then
                self:transition(sessionId, "CANCELLED", "timeout")
                continue
            end
            
            -- Recovery period ended
            if session.state == "RECOVERY" and session.recoveryEndsAt and now >= session.recoveryEndsAt then
                self:transition(sessionId, "COMPLETED", "recovery_ended")
                continue
            end
            
            -- Combo window expired (for combo skills in ACTIVE state awaiting input)
            if session.combo and session.combo.windowExpiresAt and now >= session.combo.windowExpiresAt then
                -- Window closed - either complete or start recovery
                if session.combo.currentStep >= session.combo.totalSteps then
                    self:startRecoveryOrComplete(sessionId)
                else
                    -- Mid-combo expiry - complete at current step
                    self:startRecoveryOrComplete(sessionId)
                end
            end
        end
    end)
end
```

**Benefits:**
- No callback races - single loop checks all conditions
- Deterministic ordering - all checks happen in known sequence
- Easy debugging - can log entire session state each frame
- Cancellable - just remove session from table

### 1.4 Full State in Events

Every event sent to clients includes FULL session state, not incremental deltas:

```lua
function SessionManager:emitStateChange(session: SkillSession, newState: SessionState, reason: string?)
    local payload = {
        sessionId = session.id,
        skillId = session.skillId,
        casterId = session.casterId,
        state = newState,
        reason = reason,
        
        -- Full timing info for client reconciliation
        stateEnteredAt = session.stateEnteredAt,
        executionExpiresAt = session.executionExpiresAt,
        recoveryEndsAt = session.recoveryEndsAt,
        
        -- Full combo info if applicable
        combo = session.combo and {
            currentStep = session.combo.currentStep,
            totalSteps = session.combo.totalSteps,
            windowExpiresAt = session.combo.windowExpiresAt,
        } or nil,
        
        -- Server timestamp for latency compensation
        serverTime = os.clock(),
    }
    
    dispatcher:fire("SkillSession", payload)
end
```

**Benefits:**
- Client can always reconstruct full state from any event
- Missed events don't cause permanent desync
- No need to track "what has client seen?"

### 1.5 Client Reconciliation

Client maintains a mirror of session state and reconciles on each server event:

```lua
-- Client-side SessionMirror
function SessionMirror:onServerEvent(payload)
    local sessionId = payload.sessionId
    local localSession = self.sessions[sessionId]
    
    if not localSession then
        -- Server has session we don't know about - create it
        self:createFromServer(payload)
        return
    end
    
    -- Compare server state to our prediction
    if payload.state ~= localSession.predictedState then
        -- Misprediction - reconcile
        self:reconcile(sessionId, payload)
    else
        -- Prediction correct - update timing info
        self:updateTiming(sessionId, payload)
    end
end

function SessionMirror:reconcile(sessionId: string, serverPayload)
    local localSession = self.sessions[sessionId]
    
    -- Stop any local FX/animations that shouldn't be playing
    if serverPayload.state == "CANCELLED" then
        FXCoordinator:stopAllForSession(sessionId)
        AnimationPlayer:stopForSession(sessionId)
    end
    
    -- Adopt server state as truth
    localSession.state = serverPayload.state
    localSession.predictedState = nil  -- Clear prediction
    localSession.serverConfirmedAt = os.clock()
    
    -- Update combo state
    if serverPayload.combo then
        localSession.combo = serverPayload.combo
    end
    
    -- Restart visuals from correct state if needed
    if serverPayload.state == "ACTIVE" then
        self:restartVisualsFromState(sessionId, serverPayload)
    end
end
```

---

## 2. Migration Phases

### Phase 0: Preparation (No Behavior Changes)

**Goal:** Set up infrastructure without changing existing behavior.

**Steps:**

0.1. **Create type definitions**
   - Create `src/shared/skills/SessionTypes.luau` with `SkillSession`, `SessionState`, etc.
   - Define event payload types
   - Define legal transitions table

0.2. **Create SessionManager skeleton**
   - Create `src/server/SkillsFramework/SessionManager.luau`
   - Implement basic session CRUD (create, get, delete)
   - Implement heartbeat loop (empty for now)
   - Do NOT integrate with skills yet

0.3. **Create SessionMirror skeleton**
   - Create `src/client/SkillsFramework/SessionMirror.luau`
   - Listen to `SkillSession` events
   - Store sessions locally
   - Do NOT drive visuals yet

0.4. **Add session channel**
   - Add `SkillSession` channel to networking config
   - Verify events flow server → client

**Validation:** Can create sessions on server, events arrive at client, no gameplay impact.

---

### Phase 1: Parallel Running (Shadow Mode)

**Goal:** Run new system alongside old system to validate correctness.

**Steps:**

1.1. **Emit shadow events from ExecutionService**
   - When `beginExecution()` is called, also create a SessionManager session
   - When execution completes/cancels, also transition the shadow session
   - Log any discrepancies between old and new state

1.2. **Track combo state in shadow sessions**
   - When `ComboService.requestStep()` succeeds, update shadow session's combo state
   - When combo expires, verify shadow session agrees

1.3. **Client shadow tracking**
   - SessionMirror receives events and tracks state
   - Compare shadow state to `ExecutionClient` / `ComboStateClient` state
   - Log discrepancies

1.4. **Validation period**
   - Play test extensively
   - Look for discrepancies in logs
   - Verify shadow system stays in sync with old system
   - Do NOT trust shadow system for any gameplay decisions yet

**Validation:** Shadow sessions match old system state 100% of the time.

---

### Phase 2: Client Migration (In Progress)

**Goal:** Client uses SessionMirror as source of truth instead of ExecutionClient/ComboStateClient.

**Steps:**

2.1. **SessionMirror drives permissions**
   - `ActionPermissions/Client.luau` queries `SessionMirror` instead of `ExecutionClient`
   - Keep old checks as fallback during transition

2.2. **SessionMirror drives FX coordination**
   - `SkillsClient` uses session state for FX start/stop
   - On session `CANCELLED`, stop all FX for that session
   - On session `COMPLETED`, clean up lingering FX

2.3. **SessionMirror drives animation**
   - `AnimationPlayer` receives session ID with play requests
   - Can query session state to determine correct timing
   - On reconciliation, can adjust or restart animations

2.4. **Remove client-side band-aids**
   - Remove self-healing timeouts from `ActionPermissions`
   - Remove stale state detection from `ComboStateClient`
   - These are no longer needed - SessionMirror is authoritative

**Validation:** Client visuals correctly reflect server state. No stuck states.

---

### Phase 3: Server Migration

**Goal:** Server uses SessionManager as source of truth instead of ExecutionService/ComboService.

**Steps:**

3.1. **SkillsManager uses SessionManager**
   - `useSkill()` checks `SessionManager.canStartSession()` instead of `ExecutionService.isLocked()`
   - Creates session via `SessionManager.create()` instead of `ExecutionService.begin()`

3.2. **BaseSkill uses SessionManager**
   - `beginExecution()` calls `SessionManager.transition(id, "ACTIVE")`
   - `completeExecution()` calls `SessionManager.transition(id, "COMPLETED")` or starts recovery

3.3. **BaseComboSkill uses SessionManager**
   - `advanceStep()` updates session's combo state via SessionManager
   - Window timing managed by session's `combo.windowExpiresAt`

3.4. **Heartbeat handles expiry**
   - Remove `task.delay()` callbacks for auto-completion
   - Remove `task.delay()` callbacks for combo window expiry
   - SessionManager heartbeat handles all timing

3.5. **Remove old services**
   - Delete or deprecate `ExecutionService`
   - Delete or deprecate `ComboService` (combo logic moved into SessionManager)
   - Remove `ExecutionClient` and `ComboStateClient` on client

**Validation:** Skills work end-to-end using only SessionManager. No race conditions.

---

### Phase 4: Client Prediction

**Goal:** Add proper client prediction with reconciliation.

**Steps:**

4.1. **Define predictable actions**
   - Client can predict: "I can start this skill" (if no session active)
   - Client can predict: "I can advance to step N" (if in combo window)
   - Client CANNOT predict: damage, resource changes, exact timing

4.2. **Implement optimistic updates**
   - When player presses skill key, immediately create local predicted session
   - Start animations/FX based on predicted state
   - Mark session as `predictedState = "ACTIVE"` (or similar)

4.3. **Implement reconciliation**
   - When server event arrives, compare to prediction
   - If server confirms: update timing info from server, continue visuals
   - If server rejects: stop visuals, show feedback (optional), clear session

4.4. **Handle prediction failures gracefully**
   - Animation should be interruptible (not locked to completion)
   - FX should be stoppable mid-play
   - No "phantom" effects that continue after rejection

4.5. **Latency compensation (optional)**
   - Track RTT to server
   - Start animations slightly before server confirmation is expected
   - Adjust animation speed based on server's authoritative timing

**Validation:** Skills feel responsive. Predictions are usually correct. Reconciliation is smooth.

---

### Phase 5: Cleanup & Polish

**Goal:** Remove all legacy code and polish the new system.

**Steps:**

5.1. **Remove all band-aids**
   - Remove MAX_EXECUTION_TIME timeouts
   - Remove MAX_LOCK_DURATION checks
   - Remove forceComplete() fallbacks
   - Remove stale state detection

5.2. **Consolidate event types**
   - All skill-related state flows through `SkillSession` events
   - Deprecate or remove old `SkillsEvent` phases that are redundant

5.3. **Add debugging tools**
   - Session inspector (shows all active sessions and their states)
   - State transition log (shows history of transitions for debugging)
   - Latency display (shows prediction accuracy)

5.4. **Documentation**
   - Update `copilot-instructions.md` with new architecture
   - Document SessionManager API
   - Document how to create new skills with session system

5.5. **Performance optimization**
   - Profile heartbeat loop
   - Optimize session cleanup
   - Ensure no memory leaks from long-running sessions

**Validation:** Clean codebase. No legacy code paths. System is maintainable.

---

## 3. Detailed Design: SessionManager

### 3.1 Public API

```lua
local SessionManager = {}

-- Create a new session (called when skill use is approved)
function SessionManager.create(skillId: string, casterId: string, config: SessionConfig): SkillSession

-- Get active session for a caster (nil if none)
function SessionManager.getActive(casterId: string): SkillSession?

-- Get session by ID
function SessionManager.get(sessionId: string): SkillSession?

-- Check if caster can start a new session
function SessionManager.canStart(casterId: string): boolean

-- Transition session to new state
function SessionManager.transition(sessionId: string, newState: SessionState, reason: string?): boolean

-- Advance combo step (for combo skills)
function SessionManager.advanceCombo(sessionId: string): boolean

-- Extend combo window (after successful step)
function SessionManager.extendComboWindow(sessionId: string, duration: number): void

-- Force cancel (for interrupts, death, etc.)
function SessionManager.cancel(sessionId: string, reason: string): boolean

-- Start recovery period (after final hit, before completion)
function SessionManager.startRecovery(sessionId: string, duration: number): boolean
```

### 3.2 Session Lifecycle

```
                    ┌─────────────────────────────────────────────────────────────┐
                    │                                                             │
                    ▼                                                             │
┌──────────┐    ┌─────────┐    ┌─────────┐    ┌──────────┐    ┌───────────┐      │
│   IDLE   │───▶│ CASTING │───▶│ ACTIVE  │───▶│ RECOVERY │───▶│ COMPLETED │      │
└──────────┘    └─────────┘    └─────────┘    └──────────┘    └───────────┘      │
                    │              │              │                               │
                    │              │              │                               │
                    │              ▼              ▼                               │
                    │         ┌───────────────────────┐                          │
                    └────────▶│      CANCELLED        │◀─────────────────────────┘
                              └───────────────────────┘
                                (timeout, interrupt, death)
```

**State Descriptions:**

- **IDLE** - No session exists (implicit state, not stored)
- **CASTING** - Cast time in progress (for skills with cast times)
- **ACTIVE** - Skill is executing, hits can occur
- **RECOVERY** - Post-hit recovery period, no new actions but still "busy"
- **COMPLETED** - Session ended normally, cooldown starts
- **CANCELLED** - Session ended abnormally, may or may not start cooldown

### 3.3 Combo Handling

Combo state is embedded within the session, not a separate service:

```lua
function SessionManager.advanceCombo(sessionId: string): boolean
    local session = self.sessions[sessionId]
    if not session or not session.combo then return false end
    if session.state ~= "ACTIVE" then return false end
    
    local now = os.clock()
    
    -- Check if within window
    if session.combo.windowExpiresAt and now > session.combo.windowExpiresAt then
        return false -- Window expired
    end
    
    -- Check if more steps available
    if session.combo.currentStep >= session.combo.totalSteps then
        return false -- Already at final step
    end
    
    -- Advance step
    session.combo.currentStep += 1
    session.combo.stepToken += 1
    session.combo.windowExpiresAt = nil -- Clear window until skill sets new one
    session.lastActivity = now
    
    -- Emit step event
    self:emitComboStep(session)
    
    return true
end
```

### 3.4 Timing Guarantees

The heartbeat loop provides hard guarantees:

```lua
-- Every session WILL end by executionExpiresAt
-- This is set when session is created and cannot be extended beyond MAX_SESSION_DURATION

local MAX_SESSION_DURATION = 30 -- seconds

function SessionManager.create(skillId, casterId, config)
    local now = os.clock()
    
    local session = {
        id = HttpService:GenerateGUID(),
        skillId = skillId,
        casterId = casterId,
        state = "CASTING",
        stateEnteredAt = now,
        createdAt = now,
        lastActivity = now,
        
        -- Hard timeout - session CANNOT exceed this
        executionExpiresAt = now + math.min(config.maxDuration or 10, MAX_SESSION_DURATION),
        
        combo = config.combo and {
            currentStep = 1,
            totalSteps = config.combo.steps,
            windowExpiresAt = nil,
            stepToken = 1,
        } or nil,
    }
    
    self.sessions[session.id] = session
    self.sessionsByCaster[casterId] = session
    
    self:emitStateChange(session, "CASTING", "created")
    
    return session
end
```

---

## 4. Detailed Design: SessionMirror (Client)

### 4.1 Public API

```lua
local SessionMirror = {}

-- Get local player's active session
function SessionMirror.getMySession(): SessionMirror?

-- Get any entity's active session
function SessionMirror.getSession(casterId: string): SessionMirror?

-- Check if local player is in a session
function SessionMirror.isInSession(): boolean

-- Check if local player can start a new skill
function SessionMirror.canStartSkill(): boolean

-- Create predicted session (for client prediction)
function SessionMirror.predictStart(skillId: string): PredictedSession

-- Get predicted combo step (for input gating)
function SessionMirror.getPredictedStep(): number?
```

### 4.2 Event Handling

```lua
function SessionMirror:initialize()
    local dispatcher = Networking.client()
    
    dispatcher:on("SkillSession", function(payload)
        self:onServerEvent(payload)
    end)
end

function SessionMirror:onServerEvent(payload)
    local sessionId = payload.sessionId
    local casterId = payload.casterId
    
    -- Update or create session
    local session = self.sessions[sessionId]
    
    if not session then
        session = self:createFromPayload(payload)
    else
        session = self:updateFromPayload(session, payload)
    end
    
    -- Handle prediction reconciliation for local player
    if casterId == self.localPlayerId then
        self:reconcilePrediction(session, payload)
    end
    
    -- Fire local events for other systems (FX, UI, etc.)
    self:fireLocalEvent("StateChanged", session, payload.state, payload.reason)
end
```

### 4.3 Prediction Flow

```lua
function SessionMirror:predictStart(skillId: string): PredictedSession
    -- Create optimistic local session
    local predictedSession = {
        id = "__predicted_" .. HttpService:GenerateGUID(),
        skillId = skillId,
        casterId = self.localPlayerId,
        state = "ACTIVE",
        isPredicted = true,
        predictedAt = os.clock(),
    }
    
    self.pendingPrediction = predictedSession
    
    -- Fire local event so FX/animation can start immediately
    self:fireLocalEvent("PredictedStart", predictedSession)
    
    return predictedSession
end

function SessionMirror:reconcilePrediction(serverSession, payload)
    if not self.pendingPrediction then return end
    
    -- Server responded - was our prediction correct?
    if payload.skillId == self.pendingPrediction.skillId then
        if payload.state == "ACTIVE" or payload.state == "CASTING" then
            -- Prediction confirmed! Link to real session
            self.pendingPrediction = nil
            self:fireLocalEvent("PredictionConfirmed", serverSession)
        else
            -- Prediction rejected
            self:fireLocalEvent("PredictionRejected", self.pendingPrediction, payload.reason)
            self.pendingPrediction = nil
        end
    end
end
```

---

## 5. Integration Points

### 5.1 With BaseSkill/BaseComboSkill

```lua
-- In BaseSkill:use()
function BaseSkill:use(requestData)
    -- Session already created by SkillsManager
    local session = SessionManager.get(self.sessionId)
    if not session then return end
    
    -- Transition to ACTIVE
    SessionManager.transition(self.sessionId, "ACTIVE", "skill_started")
    
    -- Set execution expiry based on skill duration
    session.executionExpiresAt = os.clock() + self:calculateDuration()
    
    -- Do skill-specific logic...
end

-- In BaseComboSkill:onComboStep()
function BaseComboSkill:onComboStep(step)
    -- Extend combo window for next input
    if step < self.config.combo.steps then
        SessionManager.extendComboWindow(self.sessionId, self.config.combo.window)
    end
    
    -- Do step-specific logic...
end

-- In BaseSkill:completeExecution()
function BaseSkill:completeExecution()
    if self.config.recovery then
        SessionManager.startRecovery(self.sessionId, self.config.recovery)
    else
        SessionManager.transition(self.sessionId, "COMPLETED", "skill_completed")
    end
end
```

### 5.2 With CooldownService

```lua
-- Listen to session completion
SessionManager.onStateChanged:Connect(function(session, newState, reason)
    if newState == "COMPLETED" then
        -- Start cooldown
        CooldownService.startCooldown(session.casterId, session.skillId)
        CooldownService.startGCD(session.casterId)
    elseif newState == "CANCELLED" then
        -- Maybe start reduced cooldown, or no cooldown
        if reason ~= "interrupt" then
            CooldownService.startCooldown(session.casterId, session.skillId)
        end
    end
end)
```

### 5.3 With FX System

```lua
-- Client-side FX coordinator listens to SessionMirror
SessionMirror.onLocalEvent:Connect(function(event, ...)
    if event == "StateChanged" then
        local session, state, reason = ...
        
        if state == "CANCELLED" or state == "COMPLETED" then
            FXCoordinator:stopAllForSession(session.id)
        end
        
    elseif event == "PredictionRejected" then
        local predictedSession, reason = ...
        FXCoordinator:stopAllForSession(predictedSession.id)
        
    elseif event == "ComboStep" then
        local session, step = ...
        FXCoordinator:playStepFX(session.skillId, step)
    end
end)
```

---

## 6. Migration Checklist

### Phase 0: Preparation
- [x] Create `src/shared/skills/SessionTypes.luau`
- [x] Create `src/server/SkillsFramework/SessionManager.luau` (skeleton)
- [x] Create `src/client/SkillsFramework/SessionMirror.luau` (skeleton)
- [x] Add `SkillSession` channel to networking
- [x] Verify basic event flow

### Phase 1: Shadow Mode
- [x] Emit shadow sessions from ExecutionService
- [x] Track combo state in shadow sessions
- [x] Client shadow tracking in SessionMirror
- [x] Add discrepancy logging
- [x] Play test and validate shadow accuracy

### Phase 2: Client Migration
- [x] ActionPermissions uses SessionMirror
- [x] SkillsClient uses SessionMirror for FX
- [x] AnimationPlayer receives session IDs
- [x] Remove client-side band-aids

### Phase 3: Server Migration
- [x] SkillsManager uses SessionManager
- [x] BaseSkill uses SessionManager
- [x] BaseComboSkill uses SessionManager
- [x] Heartbeat handles all timing
- [x] Remove ExecutionService
- [x] Remove ComboService

### Phase 4: Client Prediction
- [x] Define predictable actions
- [x] Implement optimistic updates
- [x] Implement reconciliation
- [x] Handle prediction failures gracefully
- [ ] Optional: latency compensation

### Phase 5: Cleanup
- [x] Remove all band-aids
- [x] Consolidate event types
- [x] Add debugging tools
- [x] Update documentation
- [ ] Performance optimization

---

## 7. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Shadow mode shows many discrepancies | Debug and fix old system first, or accept some discrepancies |
| Client migration breaks visuals | Keep old code paths as fallback, feature flag new system |
| Server migration breaks skills | Migrate one skill at a time, extensive testing |
| Prediction feels wrong | Tune prediction aggressiveness, add visual smoothing |
| Performance regression from heartbeat | Profile early, optimize if needed, consider spatial partitioning |

---

## 8. Success Criteria

**Phase 0-1:** Shadow system tracks 100% accurately with old system

**Phase 2:** No client-side stuck states. FX always clean up properly.

**Phase 3:** No server-side race conditions. No "mysterious" state disappearances.

**Phase 4:** Skills feel responsive (<100ms perceived latency). Mispredictions are rare and smooth.

**Phase 5:** Codebase is simpler. Adding new skills is straightforward. Debugging is easy.

---

## 9. Timeline Estimate

| Phase | Estimated Effort | Dependencies |
|-------|-----------------|--------------|
| Phase 0 | 2-4 hours | None |
| Phase 1 | 4-8 hours | Phase 0 |
| Phase 2 | 4-6 hours | Phase 1 validated |
| Phase 3 | 8-12 hours | Phase 2 |
| Phase 4 | 4-8 hours | Phase 3 |
| Phase 5 | 4-6 hours | Phase 4 |

**Total:** 26-44 hours of focused work

---

## 10. Relationship to Existing Evolution Plan

This document focuses on the **execution/combo state machine** specifically. It complements `skills_evolution_plan.md` which covers:

- **Attack Composition System** (Section 8.0) - How damage is calculated and applied
- **FX Lifecycle** (Section 3) - How effects are started/stopped
- **Stats/Query Resolver** (Sections 6, 8.1-8.4) - How stats modify skill behavior
- **Client Stats Mirror** (Section 2) - How client predicts costs/tempo

The SessionManager/SessionMirror system provides the **foundation** that those systems build on:

- Attack composition happens during the `ACTIVE` state
- FX lifecycle is driven by session state changes
- Stats queries happen when session is being created
- Client prediction uses SessionMirror to gate inputs

Both documents should be followed together for a complete system.
