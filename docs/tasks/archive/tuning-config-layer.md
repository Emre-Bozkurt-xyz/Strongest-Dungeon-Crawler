# Tuning Config Layer (First Pass)

This project now has a global tuning layer under `src/shared/Config`.

## Config Modules

- `src/shared/Config/init.luau`
  - Registry entrypoint for all tuning modules.
- `src/shared/Config/CameraConfig.luau`
  - Camera modifier profiles (for now: system menu focus modifier).
- `src/shared/Config/WorldGUIConfig.luau`
  - World GUI runtime defaults (offsets, camera-follow placement, lerp defaults).
- `src/shared/Config/UIMenuConfig.luau`
  - Shared menu panel placement/group/layout values and center-weight presets.
- `src/shared/Config/ItemInspectConfig.luau`
  - Item inspect detail line styles and excluded meta keys.

## Consumers Migrated In This Pass

- `src/client/ui/runtime/SystemPanelRuntime.luau`
  - Menu panel placement/group tuning
  - System menu camera modifier tuning
- `src/client/ui/runtime/InventoryMenuRuntime.luau`
  - Inventory panel placement tuning
  - Shared menu arc layout + center-weight presets
- `src/client/ui/runtime/EquipmentMenuRuntime.luau`
  - Equipment panel placement tuning
  - Shared menu arc layout + center-weight presets
- `src/client/ui/runtime/ItemInspectRuntime.luau`
  - Inspect panel placement tuning
  - Inspect detail line style presets
- `src/client/WorldGUIManager.luau`
  - World GUI base movement/placement defaults
- `src/client/CameraController.luau`
  - Camera baseline movement/zoom/input defaults

## High-Value Next Targets

- `src/client/WorldGUIManager.luau`
  - Base engine defaults (lerp/radius/camera offsets) should move into `UIMenuConfig` or a dedicated `WorldGUIConfig`.
- `src/client/CameraController.luau`
  - Shoulder/follow/FOV defaults should move into `CameraConfig`.
- `src/server/Inventory/EquipmentVisualService.luau`
  - Visual attach defaults (if any introduced later) should live in config instead of inline constants.
- Item generation/affix tuning (`weights`, `tier rules`, `roll scaling`)
  - Consider splitting into `LootConfig`/`AffixRollConfig` if balancing iterations increase.

## Live Dev Tuning Direction

Live tuning is now available in dev sessions through chat commands:

- `/tune help`
- `/tune get Camera.baseline.shoulderBack`
- `/tune categories`
- `/tune paths`
- `/tune paths Camera`
- `/tune paths WorldGUI.cameraPanel`
- `/tune set Camera.baseline.shoulderBack 5.2`
- `/tune nudge Camera.baseline.shoulderBack +0.1`
- `/tune setmany Camera.modifiers.systemMenuFocus shoulderBack=3 shoulderRight=3.3`
- `/tune set WorldGUI.cameraPanel.up -0.35`
- `/tune reset Camera.baseline.shoulderBack`
- `/tune reset`
- `/tune dump`
- `/tune export`

Studio console / Command Bar alternative (no chat needed):

- Server Command Bar:
  - `_G.DevTune("set Camera.baseline.shoulderBack 5.2")`
  - `_G.DevTune("set WorldGUI.cameraPanel.up -0.35")`
  - `_G.DevTune("reset")`
- Target one client:
  - `_G.DevTune(game.Players.YourName, "set Camera.baseline.shoulderBack 5.2")`
- Client Command Bar (reliable path):
  - `game.ReplicatedStorage:WaitForChild("DevTuneRemote"):FireServer("set Camera.baseline.shoulderBack 5.2")`
  - `game.ReplicatedStorage:WaitForChild("DevTuneRemote"):FireServer("help")`

Notes:
- Overrides are client-side and session-only in this pass.
- `set` supports number, boolean (`true`/`false`), and `Vector3` (`x,y,z`).
- Current runtime consumers wired for live apply:
- `CameraController` (`Camera.baseline.*`)
  - `WorldGUIManager` (`WorldGUI.*`)
  - `InventoryMenuRuntime` (`UIMenu.*`)
  - `EquipmentMenuRuntime` (`UIMenu.*`)
  - `SystemPanelRuntime` (`UIMenu.*`, `Camera.modifiers.systemMenuFocus.*`)
  - `ItemInspectRuntime` (`UIMenu.*`, `ItemInspect.*`)

To continue expanding:

1. Add a client-only `DevTuningService` that can patch select config values in memory.
2. Keep immutable source defaults in `shared/Config`.
3. Apply override layer as: `effective = deepMerge(defaults, devOverrides)`.
4. Add simple `/dump_tuning` and `/reset_tuning` developer commands.
