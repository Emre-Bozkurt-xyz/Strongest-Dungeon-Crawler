# Client-Side Skill Prediction Implementation Plan

Status: Phase 4 implemented. Phase 5 cleanup in progress.
Last updated: 2025-11-02

---

## Goals

- Zero-input-lag feel by starting animations and FX immediately after local gating.
- Server remains authoritative for damage, resources, and timing.
- Reconciliation is smooth: corrections stop or adjust visuals without desync.

---

## Current Implementation (Phase 4)

### SessionMirror as source of truth
- `SessionMirror` listens to `SkillSession` events and stores authoritative sessions.
- Predicted sessions are created locally via `SessionMirror.predictStart(...)` and marked `isPredicted`.
- When an authoritative session arrives for the same caster + skill, the prediction is replaced and cleared.

### Local gating + optimistic start
- `BaseSkill:canUseLocally()` checks cooldowns, GCD, and resources using `CooldownClient`, `SkillMetadataClient`, and `StatsClient`.
- `BasicSkill` / `BasicComboSkill` start animation + FX immediately after local gating.
- `BaseSkill:requestUseAsync()` sends the server request and handles confirm/reject callbacks.

### Combo prediction
- `ComboStateClient` is now a helper that reads `SessionMirror` state (no local state storage).
- Predicted combo step uses `SessionMirror` combo window data (opensAt/expiresAt).

### Reconciliation behavior
- Server confirmation links the real `sessionId` to the active track and updates timing metadata.
- Server rejection cancels predictions, stops FX, and stops any session-bound animations.
- Interrupts/cancellations trigger cooldowns by default; `cooldownOnCancel` can opt out per skill.

---

## Prediction Flow (Happy Path)

1. Player presses input.
2. `BaseSkill:canUseLocally()` passes.
3. `SessionMirror.predictStart(...)` creates a predicted session.
4. Animation/FX begin immediately.
5. Server response confirms and returns `sessionId`.
6. Track is bound to `sessionId` for cleanup and reconciliation.

---

## Prediction Flow (Reject / Cancel)

1. Local prediction starts.
2. Server rejects (cooldown/resources/blocked) or cancels (interrupt).
3. `BaseSkill:cancelLocalPrediction()` clears predicted session.
4. `SkillsClient` stops FX and `AnimationCoordinator` stops session-bound tracks.

---

## Key Files

- `src/client/SkillsFramework/SessionMirror.luau`
- `src/client/SkillsFramework/ComboStateClient.luau`
- `src/client/SkillsFramework/Skills/BaseSkill.luau`
- `src/client/SkillsFramework/Skills/BasicSkill.luau`
- `src/client/SkillsFramework/Skills/BasicComboSkill.luau`
- `src/client/SkillsFramework/SkillsClient.luau`
- `src/client/Animation/AnimationCoordinator.luau`
- `src/server/SkillsFramework/SkillsManager.luau`
- `src/server/SkillsFramework/SessionManager.luau`
- `src/server/SkillsFramework/SkillsConfig.luau`

---

## Phase 5 Follow-Ups

- Optional latency compensation (lead animation start using RTT).
- Debug tooling (session inspector, transition logs).
- Documentation refresh for high-level architecture guides.

---

## Notes

- `ExecutionClient` and `ExecutionStateUpdate` are removed in favor of `SessionMirror`.
- `ComboStateClient` does not maintain state; it derives from `SessionMirror`.
- Prediction only applies to local visuals; all gameplay state remains server-authoritative.
