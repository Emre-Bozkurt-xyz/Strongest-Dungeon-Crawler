# NPC System Overview

NPC logic lives under `src/server/NPCService/`. The system combines a lightweight registry with modular components that update each frame.

## Core Modules

- `NPCManager.luau`: registers models as managed NPCs. It creates a `Components` folder inside the model, exposes `addComponent/removeComponent`, and ensures stats are registered (unless `skipStats` is set).
- `ComponentManager.luau`: orchestrates component updates. It proxies common helpers from `NPCManager` and calls `Behavior.updateAll`, `Movement.updateAll`, and `Combat.updateAll` each heartbeat.
- `BehaviorToolkit/` provides shared behaviour helpers (actions, predicates, defaults) for the behaviour component.
- `NPCSpawner.luau`: spawns prefabs (stored under `NPCPrefabs/`) and optionally applies standard component sets via `ComponentManager.attachStandardSet`.

## Component Pattern

Each component module (e.g. `Components/Movement.luau`) typically exposes:

- `new(model, config?)`: attaches bookkeeping under `Components/<Name>` and stores configuration attributes.
- `updateAll(dt)`: iterates active instances and performs frame-level logic.

Components mark themselves active by setting `__active` on their folders. `NPCManager` honours this flag when reporting active components or cleaning up.

## Lifecycle

1. `NPCManager.register` stores the NPC, optionally initializes stats, and stamps `__isNPC` attributes.
2. `ComponentManager.attachStandardSet` ensures the common components (`Damageable`, `Movement`, `Combat`, `Behavior`) exist on the model.
3. `ComponentManager.updateAll` runs every heartbeat (connected from `init.server.luau`). Each component module is responsible for iterating its own instances.
4. When a model is removed from the workspace, `NPCManager.unregister` tears down stats and clears attributes.

## Extending

- Add new component modules under `Components/` and require them in `ComponentManager`.
- Register custom behaviours in `BehaviorToolkit` for reuse across NPC types.
- Prefabs can define attributes or child instances that components read on initialization.
