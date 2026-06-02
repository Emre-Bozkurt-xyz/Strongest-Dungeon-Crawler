# Interaction State Controller

## Goal

Introduce one centralized interaction policy controller so camera mode, modal menu mode, temporary cursor-unlock interaction, and world-panel interaction no longer negotiate with each other through scattered `if` statements.

This should replace the current pattern where:
- menu logic unlocks cursor directly
- legacy system-panel code unlocks cursor directly
- world-panel interaction logic guesses when mouse interaction should be allowed
- camera mode and UI mode are aware of each other in ad-hoc ways

The target is not a giant monolithic enum state machine.
The target is:
- a small set of raw state axes
- one derived interaction policy
- consumers reading resolved policy instead of coordinating pairwise

## Locked Design Decisions

1. `Precision Focus` is the player-facing name for temporary cursor interaction.
2. `InteractionStateController` is the code-facing controller name.
3. `Precision Focus` is hold-to-enter, release-to-exit.
4. `LeftAlt` is reserved for `Precision Focus`.
5. Skill-profile cycling moves off `Alt` to avoid conflict.
6. Modal menu has higher priority than `Precision Focus`.
7. World panels are only mouse-interactive during `Precision Focus`.
8. Quick interaction path remains keyboard-first:
   - `E` for loot pickup
   - menu remains modal
9. Scroll wheel is not globally owned by loot.
10. Cursor lock policy is applied centrally, not by feature modules.

## Raw State Axes

These should be stored centrally and updated by owning systems:

1. `cameraMode`
   - `Free`
   - `OverShoulder`

2. `modalOpen`
   - `true`
   - `false`

3. `precisionFocusHeld`
   - `true`
   - `false`

Future axes that can be added later without changing the core structure:

4. `abilityRetargetHeld`
5. `cutsceneLock`
6. `dialogueModal`
7. `worldInspectHeld`

## Derived Policy

The controller should derive these from the raw axes:

1. `cursorUnlocked`
2. `lookInputSuppressed`
3. `gameplayBlocked`
4. `allowsModalInteraction`
5. `allowsWorldPanelInteraction`
6. `activeSurface`
   - `Gameplay`
   - `WorldPanel`
   - `ModalUI`

Current policy rules:

1. `modalOpen` wins over everything else.
2. `Precision Focus` only grants world-panel interaction when modal menu is not open.
3. `cursorUnlocked` is true if:
   - modal menu is open, or
   - `Precision Focus` is active
4. `lookInputSuppressed` is true in `OverShoulder` when cursor is unlocked.
5. `gameplayBlocked` is true only for modal menu in phase 1.

## Current Ownership Problems

### Direct Cursor Ownership
- `src/client/ui/menu/MenuInputBridge.luau`
- `src/client/ui/runtime/SystemPanelRuntime.luau`
- `src/client/CameraController.luau`

These currently bypass a central interaction policy owner.

### Input Ownership Drift
- `src/client/input/ActionConfig.luau`
- `src/client/input/InputManager.luau`
- `src/client/Inputs.client.luau`
- `src/client/ui/controllers/LootClient.luau`

These are close to a good structure, but context ownership is still mostly implicit.

### World-Panel Interaction Drift
- `src/client/ui/controllers/LootClient.luau`
- `src/client/ui/runtime/WorldLootInspectRuntime.luau`

These currently know too much about local interaction conditions.

## Migration Phases

## Phase 0: Baseline and Terminology

- [x] Add this migration doc.
- [x] Lock the naming:
  - `Precision Focus`
  - `InteractionStateController`
- [ ] Document which systems are allowed to publish raw state.
- [ ] Document which systems are not allowed to call `CameraController:setCursorUnlocked()` directly after migration.

## Phase 1: Introduce Central Controller

- [x] Add `src/client/input/InteractionStateController.luau`.
- [x] Store raw state axes:
  - `cameraMode`
  - `modalOpen`
  - `precisionFocusHeld`
- [x] Derive effective policy in one place.
- [x] Add `onChanged` subscription API.
- [x] Add read APIs:
  - `getState()`
  - `isCursorUnlocked()`
  - `isGameplayBlocked()`
  - `allowsModalInteraction()`
  - `allowsWorldPanelInteraction()`
  - `isPrecisionFocusActive()`
- [x] Apply cursor lock/unlock policy centrally through `CameraController`.
- [x] Ensure redundant cursor reapplication is avoided.

## Phase 2: Camera Integration

- [x] Route `CameraController:setMode()` into `InteractionStateController.setCameraMode(...)`.
- [x] Ensure controller policy updates when toggling between:
  - `Free`
  - `OverShoulder`
- [x] Ensure disabling camera resets derived state cleanly if needed.
- [ ] Keep camera implementation focused on camera behavior, not UI ownership policy.

## Phase 3: Menu Integration

- [x] Make `MenuInputBridge` delegate modal state into `InteractionStateController`.
- [x] Remove direct cursor ownership from menu bridge.
- [x] Keep `MenuOrchestrator.isGameplayBlocked()` behavior stable through the controller.
- [x] Ensure modal menu still:
  - unlocks cursor
  - suppresses gameplay input
  - wins over `Precision Focus`

## Phase 4: Precision Focus Input

- [x] Reserve `LeftAlt` for `Precision Focus`.
- [x] Move skill profile cycling off `Alt`.
- [x] Add `PrecisionFocus` action bindings for:
  - press
  - release
- [x] Ensure modifier-key actions work cleanly in `InputManager`.
- [x] Wire `PrecisionFocus` action into `InteractionStateController`.
- [x] Make `Precision Focus` a hold state, not a toggle.

## Phase 5: Loot / World Panel Integration

- [x] Route loot hover/click interactivity through `InteractionStateController.allowsWorldPanelInteraction()`.
- [ ] Keep `E` quick pickup available outside `Precision Focus`.
- [x] Allow hover selection and button pickup only during `Precision Focus`.
- [ ] Keep selected row state separate from full list rebuilds.
- [ ] Re-test OTS and free-look behavior with the new policy.

## Phase 6: Legacy Cleanup

- [x] Remove direct `CameraController:setCursorUnlocked()` calls from:
  - `src/client/ui/runtime/SystemPanelRuntime.luau`
  - any remaining legacy compatibility shims
- [ ] Make any remaining compatibility methods publish into `InteractionStateController` instead.
- [ ] Audit for any future direct cursor toggles and route them centrally.

## Phase 7: Input Context Cleanup

- [ ] Improve `InputManager` dispatch semantics if context growth demands it.
- [ ] Add explicit context priority/consumption if needed.
- [ ] Move from implicit callback-side conflict checks to explicit context ownership where beneficial.
- [ ] Avoid a future where every action callback needs to know about every mode.

## Phase 8: Future Extensions

- [ ] Ability retarget / projectile steering can reuse `Precision Focus` or become a sibling held focus state.
- [ ] World inspect/detail compare panel can key off selected world-loot row.
- [ ] Additional world panels can opt into mouse interaction only through centralized policy.
- [ ] Consider explicit `activeInteractionSurface` ownership if multiple world-panel classes begin competing.

## Refactor Rules

1. No feature module should directly own cursor policy once migrated.
2. Feature modules may publish raw state or ask for resolved policy.
3. Feature modules should not pairwise negotiate with each other.
4. Derived policy belongs in the central controller only.
5. Input semantics should remain context-aware, not globally hijacked.
6. Avoid reintroducing local `if menuOpen and not cameraLocked and ...` logic in feature modules.

## First Implementation Slice

The first code slice should do only the following:

1. add `InteractionStateController`
2. route menu modal state through it
3. route camera mode through it
4. add `PrecisionFocus` hold action
5. move skill profile cycling off `Alt`
6. gate loot mouse interaction on the controller
7. migrate obvious legacy direct cursor toggles to the controller

That should be enough to prove the architecture without attempting the full cleanup in one shot.
