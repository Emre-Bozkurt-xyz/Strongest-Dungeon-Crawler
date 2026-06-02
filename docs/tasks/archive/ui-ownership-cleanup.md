# UI Ownership Cleanup Todo

## Goal
Finish the remaining structural cleanup in the client UI/world-panel/camera stack by removing internal API leaks, consolidating duplicated binding logic, and separating character-facing ownership from camera code.

## Phase 1: WorldGUI Facade Hardening
- Status: Completed
- Add explicit `WorldGUIManager` mutator APIs for panel fields still being edited through `wgm.panels[...]`.
- Add explicit `WorldGUIManager` query APIs for panel snapshot/layout-width reads.
- Migrate menu/runtime/controller callers off `(wgm :: any).panels[...]`.
- Verify no direct panel-table writes remain in UI/menu/camera-related code.

## Phase 2: Shared Binding Helpers
- Status: Completed
- Extract shared slot visual/binding helper for inventory and equipment slot rendering.
- Migrate `InventoryMenuRuntime` slot binding to the shared helper.
- Migrate `EquipmentPanelRuntime` slot binding to the shared helper.
- Replace remaining ad hoc panel descendant lookup in `ItemInspectRuntime` with `PanelBinder`.
- Remove dead duplicate local search helpers after migration.

## Phase 3: Character Facing Ownership Split
- Status: Completed
- Add a dedicated `CharacterFacingController` to own player-root yaw orientation policy.
- Move OverShoulder camera-facing writes out of `CameraController` and into the new controller.
- Move external facing / temporary orientation handling in `MovementController` to the new controller.
- Replace `ExternalFacing` attribute checks in `WorldGUIManager` with controller queries.
- Keep current behavior equivalent: OTS camera drives facing unless a temporary external facing override is active.

## Phase 4: Final Sweep
- Status: Completed
- Remove stale compatibility logic left behind by the above migrations.
- Re-scan for direct internal access, duplicate lookup code, and camera/facing ownership leaks.
- Leave any larger follow-up architecture concerns documented, not half-implemented.
