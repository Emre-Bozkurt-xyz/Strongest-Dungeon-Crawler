# Small Code Smells

These are low-priority structural follow-ups worth revisiting only if future feature work starts pushing on them.

## 1. `WorldGUIManager` is still internally large
- File: `src/client/WorldGUIManager.luau`
- Status: acceptable for now because callers no longer depend on its internal panel table.
- Revisit if new panel classes or follow behaviors start expanding the file again.

## 2. `LootClient` still mixes several responsibilities
- File: `src/client/ui/controllers/LootClient.luau`
- Current responsibilities:
  - nearby-loot discovery
  - sort/selection state
  - input handling
  - pickup dispatch
- Status: acceptable for current scope.
- Revisit if clustered loot, compare previews, or additional world interaction surfaces are added.

## 3. Modal menu presentation motion still rides the generic world-panel motion layer
- Files:
  - `src/client/ui/menu/MenuRigRuntime.luau`
  - `src/client/WorldGUIManager.luau`
- Status: functionally stable.
- Revisit only if the remaining tiny panel micro-motion becomes worth polishing.

## 4. Interaction policy is centralized, but input-context priority could still become more explicit later
- Files:
  - `src/client/input/InteractionStateController.luau`
  - `src/client/input/InputManager.luau`
- Status: good enough for current contexts.
- Revisit if multiple held-focus or targeting modes begin competing.

## Rule
Do not spend time on these unless feature work exposes real friction.
