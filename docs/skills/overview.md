# Skills Framework Overview

This project uses a unified session-based skill system. The server owns authoritative session state (timing, combo windows, completion), while clients use SessionMirror for prediction and visuals.

## Layout

- `src/server/SkillsFramework/SkillsData/` contains declarative skill definitions (name, cooldown, combo, tags).
- `src/server/SkillsFramework/SkillsConfig.luau` loads definitions, applies overrides, and instantiates skill classes.
- `src/server/SkillsFramework/Skills/` contains skill behaviors:
  - `BaseSkill.luau` handles timing resolution, resource costs, and SessionManager transitions.
  - `BaseComboSkill.luau` extends BaseSkill with per-step timing and combo window updates.
  - Individual skills (for example `Punch.luau`, `TripleStrike.luau`) implement `use` / `onComboStep`.
- `src/server/SkillsFramework/SkillsManager.luau` orchestrates skill use requests and cooldowns.
- `src/server/SkillsFramework/SessionManager.luau` owns all skill session state and heartbeat expiry.
- `src/client/SkillsFramework/SessionMirror.luau` mirrors session state on the client.

## Timing Pipeline (Server)

1. `SkillsManager.canUse()` validates cooldowns and `ActionPermissions`.
2. `SkillsManager.useSkill()` creates or advances a SessionManager session.
3. `BaseSkill:beginExecution()` transitions the session to `ACTIVE`.
4. `BaseComboSkill` extends combo windows via `SessionManager.extendComboWindow()`.
5. `BaseSkill:completeExecution()` transitions the session to `COMPLETED` (or recovery).
6. `SkillsManager` listens to SessionManager terminal states to start cooldowns and GCD.

SessionManager heartbeat enforces hard timeouts and closes combo windows deterministically.

## Resource Costs

`BaseSkill:applyResourceCost()` resolves costs through the SkillMediator pipeline and debits pools via StatsManager.
If a cost check fails, the session is cancelled with reason `insufficient_resources` and combo chains reset.

## Client Coordination

- `SessionMirror` receives `SkillSession` events and drives local state.
- `BaseSkill` performs local gating (cooldowns, GCD, resources) and starts animations/FX immediately.
- `BasicComboSkill` uses SessionMirror combo window data for predicted step selection.
- `SkillsClient` listens for terminal session events and stops FX via `Replicator` and animations via `AnimationCoordinator`.

`src/client/init.client.luau` initializes SessionMirror early so client-side gating is accurate from startup.
