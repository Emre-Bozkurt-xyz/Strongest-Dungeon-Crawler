## Menu Rig Runtime Migration

### Goal
Replace the current modal menu motion/camera coupling with a dedicated menu rig architecture.

This migration is meant to make the menu:
- stable
- predictable
- easy to tune
- easy to extend with more menu panels

It also preserves a separate path for expressive diegetic panels that are not part of the core modal menu.

### Problem Statement
The current modal menu is built on top of the generic world panel follower runtime.

That creates a structural feedback loop:
1. player transform drives panel targets
2. panel runtime smooths panel transforms
3. camera reads menu focus from live panel positions
4. camera updates player-facing context
5. loop repeats

This causes visible jitter and makes menu behavior harder to reason about.

The issue is not just individual clamp/smoothing logic.
The issue is that modal menu panels are being treated like generic follower panels.

### Design Rules
1. Modal menu panels must prioritize readability and stability over diegetic weight.
2. Generic diegetic/world-follow panels must remain supported for notifications, contextual panels, and transient UI.
3. The camera must never derive modal menu framing from live smoothed panel positions.
4. Menu placement logic must have one authority.
5. Presentation motion must be layered on top of authoritative placement, not mixed into placement solving.

### Runtime Split

#### 1. MenuRigRuntime
Owns the modal menu only.

Responsibilities:
- track active modal menu state
- own menu anchor basis
- own menu layout slots
- own menu focus point
- provide deterministic target transforms for menu panels

Characteristics:
- stable
- low-motion
- camera-aware
- deterministic

#### 2. WorldGUIManager
Continues to own generic world-follow panels.

Responsibilities:
- player-follow panels outside the modal menu
- transient floating panels
- contextual world panels
- expressive motion behavior

Characteristics:
- flexible
- support weighted motion
- support distinct settle speeds
- no authority over modal menu framing

### Panel Classes

#### Modal Menu Panels
Use MenuRigRuntime.

Examples:
- SystemPanel
- InventoryPanel
- EquipmentPanel
- ItemInspectPanel when used as part of the modal menu

#### Player Follower Panels
Use WorldGUIManager.

Examples:
- quick activation panel
- contextual prompts
- status widgets that should feel present in the world

#### Transient Panels
Use WorldGUIManager plus transient animation rules.

Examples:
- notifications
- quest updates
- pickup feedback

### Migration Phases

#### Phase 1: Camera Decoupling
Goal:
Remove the live panel position feedback loop without rewriting all placement yet.

Tasks:
- expose solved panel target positions from WorldGUIManager
- add MenuRigRuntime
- have MenuRigRuntime compute menu focus from solved targets, not live smoothed transforms
- move menu camera focus to MenuRigRuntime

Success criteria:
- camera no longer looks at weighted averages of smoothed panel positions
- menu focus is stable relative to intended panel placement

#### Phase 2: Authoritative Menu Rig Placement
Goal:
Move modal menu placement ownership out of generic panel follow logic.

Tasks:
- give MenuRigRuntime one anchor transform
- define local menu slots for Primary + Side
- compute panel target transforms from menu rig layout
- stop using per-panel player follow solving for modal menu panels

Success criteria:
- menu panels no longer independently solve follow behavior
- menu placement logic lives in one place

#### Phase 3: Presentation Motion Layer
Goal:
Add a controlled motion layer on top of menu rig placement.

Tasks:
- add optional settle easing for menu panels
- keep motion subtle and readable
- avoid altering authoritative target positions

Success criteria:
- menu retains diegetic feel without destabilizing usability

#### Phase 4: World Panel Runtime Cleanup
Goal:
Clarify the non-menu panel runtime after modal menu extraction.

Tasks:
- simplify generic follower behaviors
- document intended use cases for player-follow vs transient panels
- add per-class tuning surfaces

Success criteria:
- developers can clearly choose the correct panel class

### First Concrete Deliverables
1. `MenuRigRuntime` module
2. `WorldGUIManager.getPanelTargetPosition(panelName)`
3. camera focus using `MenuRigRuntime.getFocusPoint()`
4. remove menu camera dependence on generic world-GUI centering

### Risks
1. Inventory/item inspect visibility is partly runtime-driven rather than fully store-driven, so menu focus computation must read actual visible panel set correctly.
2. Some current layout decisions still live in per-panel runtimes; full placement centralization will require migration across those modules.
3. If player root orientation is itself unstable while modal menu is open, the rig anchor basis needs explicit ownership.

### Guardrails
1. No additional deadband/correction band-aids.
2. No reintroducing camera focus from live panel transforms.
3. No merging modal menu behavior back into generic world panel follower behavior.

### Immediate Next Steps
1. land solved-target API in WorldGUIManager
2. land MenuRigRuntime focus computation
3. route menu camera modifier to MenuRigRuntime
4. playtest jitter before doing full placement migration

## Current Status

### Completed
- `MenuRigRuntime` owns modal menu focus.
- Modal menu camera no longer derives framing from live smoothed panel positions.
- Modal menu panels now receive rig-driven target overrides.
- `MenuRigRuntime` now smooths one shared menu anchor instead of reading raw player position directly for every panel/focus solve.
- Inventory inspect is store-driven through `MenuOrchestrator` instead of being directly controlled by the inventory runtime.
- Equipment inspect now follows the same store-driven flow as inventory.
- Modal side-panel placement now has an explicit slot contract (`left` / `right` / `order`) instead of assuming every side panel stacks in one narrow path.

### Remaining
- Move the last menu-specific placement assumptions fully out of `WorldGUIManager`.
- Add a dedicated modal menu presentation-motion layer that is separate from generic world-follow motion.
- Continue fleshing out dedicated world-space inspect/loot panels separately from the modal inspect runtime.
- Flesh out additional modal side panels using the new slot contract instead of one-off logic.
- Re-test menu motion after each placement simplification pass rather than tuning symptoms.

### Related Follow-Up
- World-space loot inspect is now tracked separately in `docs/tasks/world-space-item-inspect.md`.
