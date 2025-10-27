# Entity Presence & UI Pipeline

The presence system streams nearby entities to the client and powers overhead UI elements such as health bars.

## Server: EntityInfoService

`src/server/Services/EntityInfoService.luau` runs a heartbeat loop:

1. Collects all active player characters and registered NPCs.
2. Filters them against each player’s perception radius (`StatsManager.getStatValue` for `PerceptionDistance`).
3. Emits `EntityInfoDelta` events on the `EntityInfo` channel. Payloads include stable GUIDs, positions, and optional HP reveal data (based on `PerceptionTier`).
4. Handles `EntityInfoRequest` RPCs so clients can query extra info on demand.

Entity IDs are written as attributes on the models (`EntityId`) so clients can map data back to workspace instances.

## Client Data Layer

- `src/client/EntityInfoClient.luau` subscribes to `EntityInfoDelta` and keeps a simple cache for debugging or manual requests.
- `src/client/EntityRevealStore.luau` maintains a TTL-based cache, notifies subscribers, and prunes stale entries every second.

Always call `EntityRevealStore.start()` before consuming presence data; it binds the dispatcher listener and begins pruning.

## Overhead Health Bars

`src/client/OverheadHealthService.luau` uses the reveal store to spawn and maintain world-space UI:

- Spawns clones of `ReplicatedStorage/Assets/WorldUI/OverheadHPBar`.
- Registers panels with `WorldGUIManager.luau` in `target` follow mode, snapping to the entity’s `HumanoidRootPart` when available.
- Applies density-based alpha dampening so the nearest bars remain readable.
- Hides or destroys bars when entities leave range, go off-screen, or stale out.

The actual GUI logic lives in `src/client/ui/controllers/OverheadHealthBarController.luau`. It exposes helpers for setting nameplates, absolute HP, or percentages depending on reveal tier.

## World GUI Manager

`WorldGUIManager.luau` centralises panel registration, camera-facing rotation, and smoothing. Panels declare `followMode` (`player`, `camera`, or `target`), offsets, and optional lerp speeds. Controllers should always register through the manager rather than manipulating BillboardGuis directly.
